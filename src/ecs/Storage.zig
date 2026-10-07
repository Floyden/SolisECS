const std = @import("std");
const ecs = @import("solis_ecs");

const Archetype = ecs.Archetype;
const Entity = ecs.Entity;
const Allocator = std.mem.Allocator;

const Storage = @This();

const EntityEntry = struct {
    archetype: *Archetype,
    index: usize,

    pub fn create(at: *Archetype, idx: usize) EntityEntry {
        return .{
            .archetype = at,
            .index = idx,
        };
    }
};

// TODO: Figure out how to store stable pointers
archetypes: std.ArrayList(*Archetype),
globals: *Archetype,
marked: std.ArrayList(Entity), // marked for removal

entity_map: std.AutoArrayHashMapUnmanaged(Entity, EntityEntry),

pub fn init(allocator: Allocator) !Storage {
    var archetypes: std.ArrayList(*Archetype) = .empty;
    const empty_ptr = try allocator.create(Archetype);
    empty_ptr.* = Archetype.empty;

    const globals_ptr = try allocator.create(Archetype);
    globals_ptr.* = Archetype.empty;
    try globals_ptr.addEntity(allocator, .globals);

    try archetypes.append(allocator, empty_ptr); // Create Archetype for empty entities
    try archetypes.append(allocator, globals_ptr); // Create Archetype for globals

    return Storage{
        .archetypes = archetypes,
        .globals = globals_ptr,
        .marked = .empty,
        .entity_map = try .init(allocator, &[_]Entity{.globals}, &[_]EntityEntry{.create(globals_ptr, 0)}),
    };
}

pub fn deinit(self: *Storage, gpa: Allocator) void {
    for (self.archetypes.items) |list| {
        list.deinit(gpa);
        gpa.destroy(list);
    }
    self.marked.deinit(gpa);
    self.archetypes.deinit(gpa);
    self.entity_map.deinit(gpa);
}

pub fn addEntity(self: *Storage, allocator: std.mem.Allocator, entity: Entity) !Entity {
    // Store entity in Archetype without components
    try self.archetypes.items[0].addEntity(allocator, entity);
    try self.entity_map.put(allocator, entity, .{ .archetype = self.archetypes.items[0], .index = self.archetypes.items[0].count() - 1 });
    return entity;
}

pub fn markEntity(self: *Storage, gpa: std.mem.Allocator, entity: Entity) !void {
    try self.marked.append(gpa, entity);
}

pub fn removeMarked(self: *Storage, gpa: std.mem.Allocator) void {
    for (self.marked.items) |entity| {
        self.removeEntity(gpa, entity);
    }
    self.marked.clearRetainingCapacity();
}

pub fn removeEntity(self: *Storage, gpa: std.mem.Allocator, entity: Entity) void {
    const entry = self.entity_map.get(entity) orelse return;
    entry.archetype.removeEntity(gpa, entity);
    _ = self.entity_map.swapRemove(entity);
}

fn findLocation(self: *const Storage, entity: Entity) ?EntityEntry {
    const at = self.entity_map.get(entity) orelse return null;
    std.debug.assert(at.archetype.entities.items[at.index].id == entity.id);
    return at;
}

// TODO: Instead of having a component_list for every global, use one list of globals which stores a pointer to the actual values.
// This will allow for stable global pointers.
pub fn setGlobal(self: *Storage, gpa: Allocator, comptime T: type, arg: T) !*T {
    var idx_opt = self.globals.getTypeLocation(T);
    if (idx_opt == null) {
        try self.globals.expand(gpa, T);
        idx_opt = self.globals.getTypeLocation(T);
    }

    var component_list = &self.globals.components.items[idx_opt.?];
    std.debug.assert(component_list.data.items.len == @sizeOf(T));
    component_list.getMut(T)[0] = arg;
    return &component_list.getMut(T)[0];
}

pub fn getGlobal(self: *const Storage, comptime T: type) ?*const T {
    const idx_opt = self.globals.getTypeLocation(T);
    if (idx_opt) |idx| {
        return &self.globals.components.items[idx].get(T)[0];
    }
    return null;
}

pub fn getGlobalMut(self: *const Storage, comptime T: type) ?*T {
    const idx_opt = self.globals.getTypeLocation(T);
    if (idx_opt) |idx| {
        return &self.globals.components.items[idx].getMut(T)[0];
    }
    return null;
}

pub fn get(self: *const Storage, comptime T: type, entity: Entity) ?*const T {
    const location = self.findLocation(entity) orelse return null;
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
    const location = self.findLocation(entity) orelse return null;
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
    const location = self.findLocation(entity) orelse return error.EntityNotFound;
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
        var i: usize = 0;
        for (source.components.items) |list| {
            if (list.desc.id == ecs.typeId(T)) continue;
            types.ptr[i] = list.desc;
            i += 1;
        }

        const new_archetype = try gpa.create(Archetype);
        new_archetype.* = try Archetype.init(gpa, types);
        try self.archetypes.append(gpa, new_archetype);
        var dest = self.archetypes.items[self.archetypes.items.len - 1];
        try dest.addTypeEdges.append(gpa, Archetype.Edge{ .from = dest, .to = source, .id = ecs.typeId(T) });
        try source.removeTypeEdges.append(gpa, Archetype.Edge{ .from = source, .to = dest, .id = ecs.typeId(T) });
        destination = dest;
    }

    const new_index = try source.moveEntity(gpa, destination.?, entity);
    try self.entity_map.put(gpa, entity, .create(destination.?, new_index));

    // we use swap remove in moveEntity, update the swapped entity
    if (source.entities.items.len > 0 and location.index < source.entities.items.len) {
        try self.entity_map.put(gpa, source.entities.items[location.index], .create(source, location.index));
    }
}

pub fn setComponents(self: *Storage, gpa: Allocator, entity: Entity, comptime T: type, arg: T) !*T {
    // Find Archetype of the Entity
    const location = self.findLocation(entity) orelse return error.EntityNotFound;
    const entityIdx = location.index;
    var source = location.archetype;

    // Overwrite existing entity
    const component_idx_opt = source.getTypeLocation(T);
    if (component_idx_opt) |idx| {
        const dest: *T = &source.components.items[idx].getMut(T)[entityIdx];
        dest.* = arg;
        return dest;
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
    const new_index = try source.moveEntity(gpa, destination.?, entity);
    const component_ptr: *T = &destination.?.getComponentsMut(T).?[new_index];
    component_ptr.* = arg;

    try self.entity_map.put(gpa, entity, .create(destination.?, new_index));
    // we use swap remove in moveEntity, update the swapped entity
    if (source.entities.items.len > 0 and location.index < source.entities.items.len) {
        try self.entity_map.put(gpa, source.entities.items[location.index], .create(source, location.index));
    }

    return component_ptr;
}

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Gravity = struct { g: f32 };

test "Add Components" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });

    _ = try storage.setComponents(gpa, e, Position, .{ .x = 1, .y = 2 });
    _ = try storage.setComponents(gpa, e, Velocity, .{ .x = 3, .y = 4 });

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
    _ = try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

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
    _ = try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    try std.testing.expect(storage.get(Position, e) != null);

    try storage.removeComponent(gpa, e, Position);

    try std.testing.expect(storage.findLocation(e) != null);
    try std.testing.expect(storage.get(Position, e) == null);
}

test "Remove Entity Mark/Sweep" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });
    _ = try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    try std.testing.expect(storage.get(Position, e) != null);

    try storage.markEntity(gpa, e);
    storage.removeMarked(gpa);

    try std.testing.expect(storage.get(Position, e) == null);
}

test "Remove Entity Directly" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e = try storage.addEntity(gpa, Entity{ .id = 42 });
    _ = try storage.setComponents(gpa, e, Position, .{ .x = 0, .y = 0 });

    storage.removeEntity(gpa, e);

    try std.testing.expect(storage.get(Position, e) == null);
}

test "Basic Global" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const s = try storage.setGlobal(gpa, Gravity, .{ .g = 9.81 });

    try std.testing.expectEqual(9.81, s.g);

    const s2 = storage.getGlobal(Gravity) orelse return error.TestExpectedEqual;
    try std.testing.expect(s == s2);
}

test "Mutate Global" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    _ = try storage.setGlobal(gpa, Gravity, .{ .g = 9.81 });
    _ = try storage.setGlobal(gpa, Gravity, .{ .g = 98.1 });

    const s = storage.getGlobal(Gravity) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(98.1, s.g);
}

test "Multiple Globals" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const Time = struct { t: u64 };
    const s = try storage.setGlobal(gpa, Gravity, .{ .g = 9.81 });
    const t = try storage.setGlobal(gpa, Time, .{ .t = 1 });

    try std.testing.expectEqual(9.81, s.g);
    try std.testing.expectEqual(1, t.t);

    const s2 = storage.getGlobal(Gravity) orelse return error.TestExpectedEqual;
    try std.testing.expect(s == s2);
    const t2 = storage.getGlobal(Time) orelse return error.TestExpectedEqual;
    try std.testing.expect(t == t2);
}

test "Multiple Entities" {
    const gpa = std.testing.allocator;
    var storage = try Storage.init(gpa);
    defer storage.deinit(gpa);

    const e1 = try storage.addEntity(gpa, Entity{ .id = 42 });
    const e2 = try storage.addEntity(gpa, Entity{ .id = 43 });

    _ = try storage.setComponents(gpa, e1, Position, .{ .x = 1, .y = 1 });
    _ = try storage.setComponents(gpa, e2, Position, .{ .x = 2, .y = 2 });
    _ = try storage.setComponents(gpa, e2, Velocity, .{ .x = 3, .y = 3 });
    try std.testing.expectEqual(@as(f32, 1), storage.get(Position, e1).?.x);
    try std.testing.expectEqual(@as(f32, 2), storage.get(Position, e2).?.x);
    try std.testing.expectEqual(@as(f32, 3), storage.get(Velocity, e2).?.x);
}
