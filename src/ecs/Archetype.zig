const std = @import("std");
const ecs = @import("solis_ecs");

const ArrayList = std.ArrayList;
const ComponentDesc = ecs.ComponentDesc;
const ComponentList = ecs.ComponentList;
const Entity = ecs.Entity;

const Archetype = @This();

pub const Edge = struct {
    from: *Archetype,
    to: *Archetype,
    id: ecs.TypeId,
};

pub const empty = Archetype{
    .entities = .empty,
    .components = .empty,
    .addTypeEdges = .empty,
    .removeTypeEdges = .empty,
};

entities: ArrayList(Entity),
components: ArrayList(ecs.ComponentList),
addTypeEdges: ArrayList(Edge),
removeTypeEdges: ArrayList(Edge),

fn typeLt(_: void, a: ComponentList, b: ComponentList) bool {
    return @intFromPtr(a.desc.id) < @intFromPtr(b.desc.id);
}

pub fn init(allocator: std.mem.Allocator, components: []const ComponentDesc) !Archetype {
    var componentVec: ArrayList(ComponentList) = .empty;

    for (components) |component| {
        try componentVec.append(allocator, ComponentList.init(component));
    }

    // Number of elements should be rather small, perfect for insertion sort
    std.sort.insertion(ComponentList, componentVec.items, {}, typeLt);

    return Archetype{
        .entities = .empty,
        .components = componentVec,
        .addTypeEdges = .empty,
        .removeTypeEdges = .empty,
    };
}

pub fn deinit(self: *Archetype, allocator: std.mem.Allocator) void {
    self.entities.deinit(allocator);
    for (self.components.items) |*list| {
        list.deinit(allocator);
    }
    self.components.deinit(allocator);
    self.addTypeEdges.deinit(allocator);
    self.removeTypeEdges.deinit(allocator);
}

pub fn addEntity(self: *Archetype, allocator: std.mem.Allocator, entity: Entity) !void {
    try self.entities.append(allocator, entity);
    for (self.components.items) |*list| {
        try list.appendEmpty(allocator);
    }
}

pub fn findEntity(self: *const Archetype, entity: Entity) ?usize {
    for (self.entities.items, 0..) |candidate, i| {
        if (candidate.id == entity.id) {
            return i;
        }
    }
    return null;
}

pub fn removeEntity(self: *Archetype, entity: Entity) void {
    const index = self.findEntity(entity) orelse return;

    for (self.components.items) |*component| {
        component.swapRemove(index);
    }
    _ = self.entities.swapRemove(index);
}

pub fn getTypeIdLocation(self: *const Archetype, id: ecs.TypeId) ?usize {
    for (self.components.items, 0..) |c, i| {
        if (c.desc.id == id) {
            return i;
        }
    }
    return null;
}

pub fn getTypeLocation(self: *const Archetype, comptime T: type) ?usize {
    return self.getTypeIdLocation(ecs.typeId(T));
}

pub fn hasType(self: *const Archetype, comptime T: type) bool {
    return self.hasTypeId(ecs.typeId(T));
}

pub fn hasTypeId(self: *const Archetype, id: ecs.TypeId) bool {
    return self.getTypeIdLocation(id) != null;
}

pub fn getComponents(self: *const Archetype, comptime T: type) ?[]const T {
    const index = self.getTypeLocation(T) orelse return null;
    return self.components.items[index].getMut(T);
}

pub fn getComponentsMut(self: *const Archetype, comptime T: type) ?[]T {
    const index = self.getTypeLocation(T) orelse return null;
    return self.components.items[index].getMut(T);
}

pub fn count(self: *const Archetype) usize {
    return self.entities.items.len;
}

/// Adds another component to the current archetype. The newly allocated components are not initialized
pub fn expand(self: *Archetype, allocator: std.mem.Allocator, comptime T: type) !void {
    var new_list = ComponentList.init(.get(T));
    try new_list.allocate(allocator, T, self.entities.items.len);
    for (self.components.items, 0..) |c, i| {
        if (@intFromPtr(c.desc.id) > @intFromPtr(new_list.desc.id)) {
            try self.components.insert(allocator, i, new_list);
            return;
        }
    }
    try self.components.append(allocator, new_list);
}

//---- Tests -----
const testing = std.testing;
const TypeA: type = u8;
const TypeB: type = u16;
const TypeC: type = u32;

test "Basic Types" {
    const allocator = testing.allocator;

    const descs = [_]ComponentDesc{
        .get(TypeC),
        .get(TypeA),
        .get(TypeB),
    };

    var archetype = try Archetype.init(allocator, &descs);
    defer archetype.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), archetype.count());
    try testing.expectEqual(@as(usize, 3), archetype.components.items.len);

    // Verify ordering by pointer value
    try testing.expect(@intFromPtr(archetype.components.items[0].desc.id) <
        @intFromPtr(archetype.components.items[1].desc.id));
    try testing.expect(@intFromPtr(archetype.components.items[1].desc.id) <
        @intFromPtr(archetype.components.items[2].desc.id));
}

test "Component Querying" {
    const gpa = testing.allocator;

    const descs = [_]ComponentDesc{
        .get(TypeA),
        .get(TypeB),
    };

    var archetype = try Archetype.init(gpa, &descs);
    defer archetype.deinit(gpa);

    try testing.expect(archetype.hasType(TypeA));
    try testing.expect(archetype.hasType(TypeB));
    try testing.expect(!archetype.hasType(TypeC));

    const loc_a = archetype.getTypeLocation(TypeA);
    const loc_b = archetype.getTypeLocation(TypeB);

    try testing.expect(loc_a != null);
    try testing.expect(loc_b != null);
    try testing.expect(loc_a.? != loc_b.?);
}

test "Basic Entities" {
    const gpa = testing.allocator;

    const descs = [_]ComponentDesc{
        .get(TypeA),
        .get(TypeB),
    };

    var archetype = try Archetype.init(gpa, &descs);
    defer archetype.deinit(gpa);

    const e1 = Entity{ .id = 10 };
    const e2 = Entity{ .id = 20 };

    try archetype.addEntity(gpa, e1);
    try archetype.addEntity(gpa, e2);

    try testing.expectEqual(@as(usize, 2), archetype.count());

    for (archetype.components.items) |list| {
        try testing.expectEqual(@as(usize, 2), list.count());
    }

    try testing.expectEqual(@as(?usize, 0), archetype.findEntity(e1));
    try testing.expectEqual(@as(?usize, 1), archetype.findEntity(e2));
    try testing.expectEqual(@as(?usize, null), archetype.findEntity(.{ .id = 99 }));
}

test "removeEntity" {
    const gpa = testing.allocator;

    const descs = [_]ComponentDesc{
        .get(TypeA),
        .get(TypeB),
    };

    var archetype = try Archetype.init(gpa, &descs);
    defer archetype.deinit(gpa);

    const e1 = Entity{ .id = 1 };
    const e2 = Entity{ .id = 2 };
    const e3 = Entity{ .id = 3 };

    try archetype.addEntity(gpa, e1);
    try archetype.addEntity(gpa, e2);
    try archetype.addEntity(gpa, e3);

    archetype.removeEntity(e2);

    try testing.expectEqual(@as(usize, 2), archetype.count());
    try testing.expect(archetype.findEntity(e2) == null);

    for (archetype.components.items) |list| {
        try testing.expectEqual(@as(usize, 2), list.count());
    }

    archetype.removeEntity(e2);
    try testing.expectEqual(@as(usize, 2), archetype.count());
    for (archetype.components.items) |list| {
        try testing.expectEqual(@as(usize, 2), list.count());
    }
}
