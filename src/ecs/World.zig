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

pub fn create(self: *World, allocator: Allocator) !Entity {
    defer self.nextEntity.id += 1;
    return self.storage.addEntity(allocator, self.nextEntity);
}

/// Insert an existing entity into the world. Used for internal entities.
pub fn insertEntity(self: *World, gpa: Allocator, entity: Entity) !void {
    _ = try self.storage.addEntity(gpa, entity);
}

pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !*T {
    return try self.storage.setComponents(self.allocator, entity, T, arg);
}

pub fn get(self: *World, entity: Entity, comptime T: type) ?*const T {
    return self.storage.get(T, entity);
}

pub fn getMut(self: *World, entity: Entity, comptime T: type) ?*T {
    return self.storage.getMut(T, entity);
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
    };
    const ctx: *Context = try gpa.create(Context);
    const tuple = &ctx.params;
    ctx.callback = system;

    const system_entity = try self.create(gpa);
    const params = system_info.@"fn".params;
    inline for (params, 0..) |param, i| {
        const field_name = comptime std.fmt.comptimePrint("{}", .{i});
        switch (param.type.?) {
            std.mem.Allocator => @field(tuple.*, field_name) = self.allocator,
            ecs.Commands, *const ecs.Commands => @compileError("Found const Commands as system parameter, use *Commands"),
            *ecs.Commands => @field(tuple.*, field_name) = &self.commands,
            World => @compileError("World as parameter not supported, use *World or *const World"),
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
