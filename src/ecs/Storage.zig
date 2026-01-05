const std = @import("std");
const ecs = @import("solis_ecs");

const Archetype = ecs.Archetype;
const Entity = ecs.Entity;
const Allocator = std.mem.Allocator;

const Storage = @This();

// TODO: Figure out how to store stable pointers
archetypes: std.ArrayList(*Archetype),
singletons: *Archetype,

pub fn init(allocator: Allocator) !Storage {
    var archetypes: std.ArrayList(*Archetype) = .empty;
    const empty_ptr = try allocator.create(Archetype);
    empty_ptr.* = Archetype.empty;

    const singletons_ptr = try allocator.create(Archetype);
    singletons_ptr.* = Archetype.empty;
    try singletons_ptr.addEntity(allocator, .singletons);

    try archetypes.append(allocator, empty_ptr); // Create Archetype for empty entities
    try archetypes.append(allocator, singletons_ptr); // Create Archetype for singletons

    return Storage{
        .archetypes = archetypes,
        .singletons = singletons_ptr,
    };
}

pub fn deinit(self: *Storage, gpa: Allocator) void {
    for (self.archetypes.items) |list| {
        list.deinit(gpa);
        gpa.destroy(list);
    }
    self.archetypes.deinit(gpa);
}

pub fn addEntity(self: *Storage, allocator: std.mem.Allocator, entity: Entity) !Entity {
    // Store entity in Archetype without components
    try self.archetypes.items[0].addEntity(allocator, entity);
    return entity;
}

pub fn markEntity(self: *Storage, entity: Entity) void {
    _ = entity;
    _ = self;
}

pub fn removeMarked(self: *Storage) void {
    _ = self;
}

pub fn removeEntity(self: *Storage, entity: Entity) void {
    for (self.archetypes.items) |i| {
        if (i.findEntity(entity)) |_| {
            i.removeEntity(entity);
            return;
        }
    }
}

fn findArchetype(self: *const Storage, entity: Entity) ?struct { index: usize, archetype: *Archetype } {
    for (0..self.archetypes.items.len) |i| {
        if (self.archetypes.items[i].findEntity(entity)) |value| {
            return .{ .index = value, .archetype = self.archetypes.items[i] };
        }
    }
    return null;
}

pub fn setSingleton(self: *Storage, gpa: Allocator, comptime T: type, arg: T) !*T {
    var idx_opt = self.singletons.getTypeLocation(T);
    if (idx_opt == null) {
        try self.singletons.expand(gpa, T);
        idx_opt = self.singletons.getTypeLocation(T);
    }

    var component_list = self.singletons.components.items[idx_opt.?];
    std.debug.assert(component_list.data.items.len == @sizeOf(T));
    component_list.getMut(T)[0] = arg;
    return &component_list.getMut(T)[0];
}

pub fn getSingleton(self: *const Storage, comptime T: type) ?*T {
    const idx_opt = self.singletons.getTypeLocation(T);
    if (idx_opt) |idx| {
        return &self.singletons.components.items[idx].getMut(T)[0];
    }
    return null;
}

pub fn get(self: *const Storage, comptime T: type, entity: Entity) ?*const T {
    const location = self.findArchetype(entity) orelse return null;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (list.desc.id == ecs.typeId(T)) {
            if (@sizeOf(T) == 0)
                return @ptrCast(list.get(T));
            return &list.get(T)[index];
        }
    }
    return null;
}

pub fn getMut(self: *const Storage, comptime T: type, entity: Entity) ?*T {
    const location = self.findArchetype(entity) orelse return null;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (list.desc.id == ecs.typeId(T)) {
            if (@sizeOf(T) == 0)
                return @ptrCast(list.getMut(T));

            return &list.getMut(T)[index];
        }
    }
    return null;
}

pub fn removeComponent(self: *Storage, gpa: Allocator, entity: Entity, comptime T: type) !void {
    // Find Archetype of the Entity
    const location = self.findArchetype(entity) orelse return error.EntityNotFound;
    const entityIdx = location.index;
    var source = location.archetype;

    // Find new destination
    var destination: ?*Archetype = null;
    for (source.removeTypeEdges.items) |edge| {
        if (edge.id == ecs.typeId(T)) {
            destination = edge.to;
            break;
        }
    }

    // Create new Archetype if the destination is not found
    if (destination == null) {
        var types = try gpa.alloc(ecs.ComponentDesc, source.components.items.len - 1);
        defer gpa.free(types);
        for (source.components.items, 0..) |list, i| {
            if (list.desc.id == ecs.typeId(T)) continue;
            types.ptr[i] = list.desc;
        }

        const new_archetype = try gpa.create(Archetype);
        new_archetype.* = try Archetype.init(gpa, types);
        try self.archetypes.append(gpa, new_archetype);
        var dest = self.archetypes.items[self.archetypes.items.len - 1];
        try dest.addTypeEdges.append(gpa, Archetype.Edge{ .from = dest, .to = source, .id = ecs.typeId(T) });
        try source.removeTypeEdges.append(gpa, Archetype.Edge{ .from = source, .to = dest, .id = ecs.typeId(T) });
        destination = dest;
    }

    // Move entity
    try destination.?.entities.append(gpa, entity);

    for (destination.?.components.items) |*component| {
        const index = source.getTypeIdLocation(component.desc.id);
        try component.appendRaw(gpa, source.components.items[index.?].getSingleRaw(entityIdx));
    }
    source.removeEntity(entity);
}

pub fn setComponents(self: *Storage, gpa: Allocator, entity: Entity, comptime T: type, arg: T) !void {
    // Find Archetype of the Entity
    const location = self.findArchetype(entity) orelse return error.EntityNotFound;
    const entityIdx = location.index;
    var source = location.archetype;

    // Overwrite existing entity
    const component_idx_opt = source.getTypeLocation(T);
    if (component_idx_opt) |idx| {
        source.components.items[idx].getMut(T)[entityIdx] = arg;
        return;
    }

    // Find new destination
    var destination: ?*Archetype = null;
    for (source.addTypeEdges.items) |edge| {
        if (edge.id == ecs.typeId(T)) {
            destination = edge.to;
            break;
        }
    }

    // Create new Archetype if the destination is not found
    if (destination == null) {
        var types = try gpa.alloc(ecs.ComponentDesc, source.components.items.len + 1);
        defer gpa.free(types);
        for (source.components.items, 0..) |list, i| {
            types.ptr[i] = list.desc;
        }
        types[source.components.items.len] = ecs.ComponentDesc.get(T);

        const new_archetype = try gpa.create(Archetype);
        new_archetype.* = try Archetype.init(gpa, types);
        try self.archetypes.append(gpa, new_archetype);
        var dest = self.archetypes.items[self.archetypes.items.len - 1];
        try dest.removeTypeEdges.append(gpa, Archetype.Edge{ .from = dest, .to = source, .id = ecs.typeId(T) });
        try source.addTypeEdges.append(gpa, Archetype.Edge{ .from = source, .to = dest, .id = ecs.typeId(T) });
        destination = dest;
    }

    // Move entity
    try destination.?.entities.append(gpa, entity);

    for (destination.?.components.items) |*component| {
        const index = source.getTypeIdLocation(component.desc.id);
        if (index) |i| {
            try component.appendRaw(gpa, source.components.items[i].getSingleRaw(entityIdx));
        } else {
            try component.append(gpa, T, arg);
        }
    }
    source.removeEntity(entity);
}

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Gravity = struct { g: f32 };

test "Add Components" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });

    try storage.setComponents(gpa, e, Position, .{ .x = 1, .y = 2 });
    try storage.setComponents(gpa, e, Velocity, .{ .x = 3, .y = 4 });

    const pos = storage.get(Position, e) orelse return error.NullValue;
    try std.testing.expectEqual(@as(f32, 1), pos.x);
    try std.testing.expectEqual(@as(f32, 2), pos.y);

    const vel = storage.get(Velocity, e) orelse return error.NullValue;
    try std.testing.expectEqual(@as(f32, 3), vel.x);
    try std.testing.expectEqual(@as(f32, 4), vel.y);
}

test "Modify Components" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });
    try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    const pos = storage.getMut(Position, e) orelse return error.NullValue;
    pos.x = 10;
    pos.y = 20;

    const pos2 = storage.getMut(Position, e) orelse return error.NullValue;
    try std.testing.expectEqual(@as(f32, 10), pos2.x);
    try std.testing.expectEqual(@as(f32, 20), pos2.y);
}

test "Remove Component directly" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });
    try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    try std.testing.expect(storage.get(Position, e) != null);

    try storage.removeComponent(gpa, e, Position);

    try std.testing.expect(storage.findArchetype(e) != null);
    try std.testing.expect(storage.get(Position, e) == null);
}

// TODO: Not yet implemented
// test "Remove Entity Mark/Sweep" {
//     const gpa = std.testing.allocator;
//     var storage = try Storage.init(gpa);
//     defer storage.deinit(gpa);
//
//     const e = try storage.addEntity(gpa, Entity{ .id = 42 });
//     try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });
//
//     try std.testing.expect(storage.get(Position, e) != null);
//
//     storage.markEntity(e);
//     storage.removeMarked();
//
//     try std.testing.expect(storage.get(Position, e) == null);
// }

test "Remove Entity Directly" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });
    try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    storage.removeEntity(e);

    try std.testing.expect(storage.get(Position, e) == null);
}

test "Basic Singleton" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const s = try storage.setSingleton(gpa, Gravity, .{ .g = 9.81 });

    try std.testing.expectEqual(9.81, s.g);

    const s2 = storage.getSingleton(Gravity) orelse return error.TestExpectedEqual;
    try std.testing.expect(s == s2);
}

test "Mutate Singleton" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    _ = try storage.setSingleton(gpa, Gravity, .{ .g = 9.81 });
    _ = try storage.setSingleton(gpa, Gravity, .{ .g = 98.1 });

    const s = storage.getSingleton(Gravity) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(98.1, s.g);
}

test "Multiple Entities" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e1 = try storage.addEntity(gpa, Entity{ .id = 42 });
    const e2 = try storage.addEntity(gpa, Entity{ .id = 43 });

    try storage.setComponents(gpa, e1, Position, .{ .x = 1, .y = 1 });
    try storage.setComponents(gpa, e2, Position, .{ .x = 2, .y = 2 });
    try storage.setComponents(gpa, e2, Velocity, .{ .x = 3, .y = 3 });
    try std.testing.expectEqual(@as(f32, 1), storage.get(Position, e1).?.x);
    try std.testing.expectEqual(@as(f32, 2), storage.get(Position, e2).?.x);
    try std.testing.expectEqual(@as(f32, 3), storage.get(Velocity, e2).?.x);
}
