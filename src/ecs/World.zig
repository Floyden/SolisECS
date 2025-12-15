const std = @import("std");
const ecs = @import("ecs.zig");
const iter = @import("iter.zig");
const single = @import("single.zig");
const type_id = @import("type_id.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = @import("Entity.zig");
const ComponentDesc = @import("components.zig").Description;
const SystemDesc = ecs.SystemDesc;
const Storage = @import("Storage.zig");
const pairs = @import("pairs.zig");
pub const Iter = iter.Iter;
pub const Query = iter.Query;

const World = @This();

allocator: Allocator,
components: std.AutoHashMapUnmanaged(ComponentDesc, void),
systems: ArrayList(SystemDesc),
storage: Storage,
pairStorage: pairs.Storage,

nextEntity: Entity,
singletons: Entity,

pub fn init(allocator: Allocator) !World {
    var world = World{
        .allocator = allocator,
        .components = .empty,
        .systems = .empty,
        .nextEntity = .{ .id = 1 },
        .singletons = .{ .id = -1 },
        .storage = undefined,
        .pairStorage = .empty,
    };

    world.storage = try .init(allocator, world.singletons);

    return world;
}

pub fn deinit(self: *World) void {
    for (self.systems.items) |*system| {
        system.params.deinit(self.allocator);
    }
    self.systems.deinit(self.allocator);
    self.components.deinit(self.allocator);
    self.pairStorage.deinit(self.allocator);
    self.storage.deinit();
}

// [TODO] implement
pub fn register(self: *World, allocator: std.mem.Allocator, comptime T: type) !void {
    try self.components.put(allocator, ComponentDesc.get(T), {});
}

pub fn setSingleton(self: *World, comptime T: type, arg: T) !*T {
    try self.components.put(self.allocator, ComponentDesc.get(T), {});
    return try self.storage.setSingleton(T, arg);
}

pub fn getSingleton(self: *World, comptime T: type) ?*T {
    return self.storage.getMut(T, self.singletons);
}

pub fn addPair(self: *World, a: Entity, comptime R: type, b: Entity) !void {
    try self.pairStorage.add(self.allocator, .{ .src = a, .dst = b, .relation = type_id.typeId(R) });
}

pub fn removePair(self: *World, a: Entity, comptime R: type, b: Entity) void {
    self.pairStorage.remove(.{ .src = a, .dst = b, .relation = type_id.typeId(R) });
}

pub fn hasPair(self: *World, a: Entity, comptime R: type, b: Entity) bool {
    return self.pairStorage.contains(.{ .src = a, .dst = b, .relation = type_id.typeId(R) });
}

// [TODO] figure out how to store the parameter types
pub fn addSystem(self: *World, callback: fn (*Iter) void, comptime args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);

    const field_info = args_type_info.Struct.fields;
    var desc = SystemDesc{ .callback = callback, .params = undefined };
    desc.params = ArrayList([:0]const u8).init(self.allocator);

    inline for (0..field_info.len) |i| {
        const field = @field(args, field_info[i].name);
        try desc.params.append(@typeName(field));
    }

    try self.systems.append(desc);
}

pub fn step(self: *World) !void {
    for (self.systems.items) |*system| {
        var query = try Query.init(self.allocator, self, system.params.items);
        lArc: for (self.storage.archetypes.items) |*archetype| {
            for (system.params.items) |param| {
                if (!archetype.hasTypeId(param)) continue :lArc;
            }
            try query.addArchetype(archetype);
        }
        for (0..query.archetypes.items.len) |i| {
            var it = query.iter(i);
            system.callback(&it);
        }
    }
}

pub fn create(self: *World, allocator: std.mem.Allocator) !Entity {
    defer self.nextEntity.id += 1;
    return self.storage.addEntity(allocator, self.nextEntity);
}

pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !void {
    try self.storage.setComponents(entity, T, arg);
}

pub fn get(self: *World, entity: Entity, comptime T: type) ?*const T {
    return self.storage.get(T, entity);
}

pub fn getMut(self: *World, entity: Entity, comptime T: type) ?*T {
    return self.storage.getMut(T, entity);
}
