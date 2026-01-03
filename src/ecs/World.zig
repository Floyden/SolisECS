const std = @import("std");
const ecs = @import("solis_ecs");

const typeId = ecs.typeId;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = ecs.Entity;
const ComponentDesc = ecs.ComponentDesc;

const World = @This();

allocator: Allocator,
components: std.AutoHashMapUnmanaged(ComponentDesc, void),
storage: ecs.Storage,
pairStorage: ecs.PairStorage,

nextEntity: Entity,

pub fn init(allocator: Allocator) !World {
    var world = World{
        .allocator = allocator,
        .components = .empty,
        .nextEntity = .{ .id = 1 },
        .storage = undefined,
        .pairStorage = .empty,
    };

    world.storage = try .init(allocator);

    return world;
}

pub fn deinit(self: *World) void {
    self.components.deinit(self.allocator);
    self.pairStorage.deinit(self.allocator);
    self.storage.deinit(self.allocator);
}

// [TODO] implement
pub fn register(self: *World, allocator: Allocator, comptime T: type) !void {
    try self.components.put(allocator, ComponentDesc.get(T), {});
}

pub fn setSingleton(self: *World, comptime T: type, arg: T) !*T {
    try self.components.put(self.allocator, ComponentDesc.get(T), {});
    return try self.storage.setSingleton(self.allocator, T, arg);
}

pub fn getSingleton(self: *World, comptime T: type) ?*T {
    return self.storage.getMut(T, .singletons);
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

pub fn create(self: *World, allocator: Allocator) !Entity {
    defer self.nextEntity.id += 1;
    return self.storage.addEntity(allocator, self.nextEntity);
}

pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !void {
    try self.storage.setComponents(self.allocator, entity, T, arg);
}

pub fn get(self: *World, entity: Entity, comptime T: type) ?*const T {
    return self.storage.get(T, entity);
}

pub fn getMut(self: *World, entity: Entity, comptime T: type) ?*T {
    return self.storage.getMut(T, entity);
}
