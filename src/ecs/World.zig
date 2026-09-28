const std = @import("std");
const ecs = @import("solis_ecs");

const typeId = ecs.typeId;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = ecs.Entity;
const ComponentDesc = ecs.ComponentDesc;
const Query = ecs.Query;
const QueryIter = ecs.QueryIter;

const World = @This();

const PointerOnlyParameter: bool = true;

allocator: Allocator,
commands: ecs.Commands,
components: std.AutoHashMapUnmanaged(ComponentDesc, void),
storage: ecs.Storage,
pairStorage: ecs.PairStorage,

nextEntity: Entity,

frame: usize,

pub fn init(allocator: Allocator) !World {
    var world = World{
        .allocator = allocator,
        .commands = .init(),
        .components = .empty,
        .nextEntity = .{ .id = 1 },
        .storage = try .init(allocator),
        .pairStorage = .empty,
        .frame = 0,
    };
    try ecs.Schedule.init(allocator, &world);

    return world;
}

pub fn deinit(self: *World) void {
    self.commands.deinit(self.allocator);
    self.storage.deinit(self.allocator);
    self.pairStorage.deinit(self.allocator);
    self.components.deinit(self.allocator);
}

// [TODO] implement
pub fn register(self: *World, allocator: Allocator, comptime T: type) !void {
    try self.components.put(allocator, ComponentDesc.get(T), {});
}

pub fn setGlobal(self: *World, comptime T: type, arg: T) !*T {
    try self.components.put(self.allocator, ComponentDesc.get(T), {});
    return try self.storage.setGlobal(self.allocator, T, arg);
}

pub fn getGlobal(self: *World, comptime T: type) ?*const T {
    return self.storage.get(T, .globals);
}

pub fn getGlobalMut(self: *World, comptime T: type) ?*T {
    return self.storage.getMut(T, .globals);
}

pub fn addPair(self: *World, a: Entity, comptime R: type, b: Entity) !void {
    try self.pairStorage.add(self.allocator, .{ .src = a, .dst = b, .relation = typeId(R) });
}

pub fn removePair(self: *World, a: Entity, comptime R: type, b: Entity) void {
    self.pairStorage.remove(.{ .src = a, .dst = b, .relation = typeId(R) });
}

pub fn hasPair(self: *World, a: Entity, comptime R: type, b: Entity) bool {
    return self.pairStorage.contains(.{ .src = a, .dst = b, .relation = typeId(R) });
}

pub fn traverse(self: *const World, desc: ecs.TraverseDesc) !ecs.PairStorage.TraverseIter {
    return self.pairStorage.traverse(self.allocator, desc);
}

pub fn createEmpty(self: *World, allocator: Allocator) !Entity {
    defer self.nextEntity.id += 1;
    return self.storage.addEntity(allocator, self.nextEntity);
}

/// Wrapper around calling `createEmpty` and `add`
pub fn create(self: *World, gpa: Allocator, components: anytype) !Entity {
    const entity = try self.createEmpty(gpa);
    errdefer self.storage.removeEntity(gpa, entity);
    try self.add(gpa, entity, components);
    return entity;
}

/// Add a component or a tuple of components to the entity
pub fn add(self: *World, gpa: Allocator, entity: Entity, components: anytype) !void {
    const ComponentT = @TypeOf(components);
    const component_desc = @typeInfo(ComponentT);
    if (component_desc != .@"struct") return error.ComponentType;
    // TODO: [Slow] The current implementation might cause the entity to be moved often between archetypes.

    if (component_desc.@"struct".is_tuple) {
        inline for (components) |component| {
            _ = try self.add(gpa, entity, component);
        }
        return;
    }

    _ = try self.set(entity, ComponentT, components);
    if (@hasDecl(ComponentT, "Requires")) {
        inline for (ComponentT.Requires) |Req| {
            if (!self.has(entity, Req)) {
                if (@hasDecl(Req, "default")) {
                    try self.add(gpa, entity, Req.default);
                } else {
                    try self.add(gpa, entity, Req{});
                }
            }
        }
    }
}

/// Insert an existing entity into the world. Used for internal entities.
pub fn insertEntity(self: *World, gpa: Allocator, entity: Entity) !void {
    _ = try self.storage.addEntity(gpa, entity);
}

/// Set the component to the given value. Will add the component to the entity if not present.
pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !*T {
    return try self.storage.setComponents(self.allocator, entity, T, arg);
}

pub fn get(self: *World, entity: Entity, comptime T: type) ?*const T {
    return self.storage.get(T, entity);
}

pub fn getMut(self: *World, entity: Entity, comptime T: type) ?*T {
    return self.storage.getMut(T, entity);
}

pub fn has(self: *World, entity: Entity, comptime T: type) bool {
    return self.get(entity, T) != null;
}

pub fn addSystem(self: *World, gpa: Allocator, system: anytype, desc: ecs.SystemDesc) !void {
    const SystemType = @TypeOf(system);
    const system_info = @typeInfo(SystemType);
    if (system_info != .@"fn") @compileError("Only Functions supported in World.addSystem");

    const TupleType = std.meta.ArgsTuple(SystemType);

    const Context = struct {
        callback: *const SystemType,
        params: TupleType,

        fn deinit(self_ctx: *@This(), gpa_ctx: Allocator) void {
            inline for (&self_ctx.params) |*param| {
                const T = @TypeOf(param.*);
                if (@typeInfo(T) == .pointer) continue;
                if (@hasDecl(T, "deinit")) {
                    param.deinit(gpa_ctx);
                }
            }
            gpa_ctx.destroy(self_ctx);
        }

        fn invoke(self_ctx: *const @This()) void {
            @call(.auto, self_ctx.callback, self_ctx.params);
        }

        fn prepare(self_ctx: *@This(), world: *World) void {
            inline for (&self_ctx.params) |*param| {
                const T = @TypeOf(param.*);
                const Base = if (@typeInfo(T) == .pointer) std.meta.Child(T) else T;
                if (comptime @hasDecl(Base, "prepare")) {
                    param.prepare(world);
                }
            }
        }
    };
    const ctx: *Context = try gpa.create(Context);
    const tuple = &ctx.params;
    ctx.callback = system;

    const system_entity = try self.createEmpty(gpa);
    const params = system_info.@"fn".params;
    inline for (params, 0..) |param, i| {
        const T = param.type.?;
        const Base = if (@typeInfo(T) == .pointer) std.meta.Child(T) else T;
        const field_name = comptime std.fmt.comptimePrint("{}", .{i});

        if (comptime @hasDecl(Base, "PointerOnlyParameter") and Base.PointerOnlyParameter and Base == T) {
            const err_msg = comptime std.fmt.comptimePrint("Found {} as pointer only system parameter, use *{} instead", .{ T, T });
            @compileError(err_msg);
        }

        switch (T) {
            std.mem.Allocator => @field(tuple.*, field_name) = self.allocator,
            *ecs.Commands => @field(tuple.*, field_name) = &self.commands,
            *World, *const World => {
                @field(tuple.*, field_name) = self;
            },
            else => |t| {
                @field(tuple.*, field_name) = try t.init(gpa, self, system_entity);
            },
        }
    }

    const system_component = ecs.System{
        .callback = @ptrCast(&Context.invoke),
        .deinit_cb = @ptrCast(&Context.deinit),
        .prepare_cb = @ptrCast(&Context.prepare),
        .context = ctx,
    };

    _ = try self.set(system_entity, ecs.System, system_component);
    try self.addPair(system_entity, Entity.DependsOn, desc.stage);
}

pub fn step(self: *World) !void {
    self.frame += 1;
    try ecs.Schedule.run_pipeline(self);
    self.storage.removeMarked(self.allocator);
}

// ------ Tests ------

const Foo = struct { x: u32 = 4 };
const Bar = struct {
    const Requires = .{Foo};
    y: u32,
};

test "create" {
    const gpa = std.testing.allocator;
    var world = try World.init(gpa);
    defer world.deinit();

    const e1 = try world.create(gpa, Foo{ .x = 1 });
    try std.testing.expect(world.get(e1, Foo).?.x == 1);

    const e2 = try world.create(gpa, Bar{ .y = 2 });
    try std.testing.expect(world.get(e2, Bar).?.y == 2);
    try std.testing.expect(world.get(e2, Foo).?.x == 4);
}
