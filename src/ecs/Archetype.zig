const std = @import("std");
const _component = @import("components.zig");
const type_id = @import("type_id.zig");
const Entity = @import("Entity.zig");

const ArrayList = std.ArrayList;
const ComponentDesc = _component.Description;
const ComponentList = _component.List;

const Archetype = @This();

pub const Edge = struct {
    from: *Archetype,
    to: *Archetype,
    typeName: [:0]const u8,
};

pub const empty = Archetype{
    .entities = .empty,
    .components = .empty,
    .addTypeEdges = .empty,
    .removeTypeEdges = .empty,
};

entities: ArrayList(Entity),
components: ArrayList(ComponentList),
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
    const index = self.findEntity(entity);
    if (index == null) return;

    for (self.components.items) |*component| {
        component.swapRemove(index.?);
    }
    _ = self.entities.swapRemove(index.?);
}

pub fn getTypeLocation(self: *const Archetype, id: type_id.TypeId) ?usize {
    for (self.components.items, 0..) |c, i| {
        if (c.desc.id == id) {
            return i;
        }
    }
    return null;
}

pub fn hasType(self: *const Archetype, id: type_id.TypeId) bool {
    return self.getTypeLocation(id) != null;
}

pub fn count(self: *const Archetype) usize {
    return self.entities.items.len;
}

pub fn expand(self: *const Archetype, allocator: std.mem.Allocator, component: ComponentDesc) void {
    for (self.components.items, 0..) |c, i| {
        if (@intFromPtr(c.desc.id) > @intFromPtr(component.id)) {
            self.components.insert(allocator, i, .init(component));
            return;
        }
    }
    self.components.append(allocator, .init(component));
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

    try testing.expect(archetype.hasType(type_id.typeId(TypeA)));
    try testing.expect(archetype.hasType(type_id.typeId(TypeB)));
    try testing.expect(!archetype.hasType(type_id.typeId(TypeC)));

    const loc_a = archetype.getTypeLocation(type_id.typeId(TypeA));
    const loc_b = archetype.getTypeLocation(type_id.typeId(TypeB));

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
