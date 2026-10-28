const std = @import("std");
const ecs = @import("solis_ecs");

const ArrayList = std.ArrayList;
const ComponentDesc = ecs.ComponentDesc;
const ComponentList = ecs.ComponentList;
const Entity = ecs.Entity;
const Frame = ecs.World.Frame;

const Archetype = @This();

pub const Edge = struct {
    from: *Archetype,
    to: *Archetype,
    id: ecs.TypeId,
};

pub const empty = Archetype{
    .entities = .empty,
    .components = .empty,
    .add_type_edges = .empty,
    .remove_type_edges = .empty,
    .last_modified = .empty,
};

entities: ArrayList(Entity),
components: ArrayList(ecs.ComponentList),
last_modified: ArrayList(?Frame),
add_type_edges: ArrayList(Edge),
remove_type_edges: ArrayList(Edge),

fn typeLt(_: void, a: ComponentList, b: ComponentList) bool {
    return @intFromPtr(a.desc.id) < @intFromPtr(b.desc.id);
}

pub fn init(gpa: std.mem.Allocator, components: []const ComponentDesc) !Archetype {
    var component_vec: ArrayList(ComponentList) = try .initCapacity(gpa, components.len);
    var frame_vec: ArrayList(?Frame) = try .initCapacity(gpa, components.len);

    for (components) |component| {
        component_vec.appendAssumeCapacity(ComponentList.init(component));
        frame_vec.appendAssumeCapacity(null);
    }

    // Number of elements should be rather small, perfect for insertion sort
    std.sort.insertion(ComponentList, component_vec.items, {}, typeLt);

    return Archetype{
        .entities = .empty,
        .components = component_vec,
        .last_modified = frame_vec,
        .add_type_edges = .empty,
        .remove_type_edges = .empty,
    };
}

pub fn deinit(self: *Archetype, gpa: std.mem.Allocator) void {
    self.last_modified.deinit(gpa);
    self.entities.deinit(gpa);
    for (self.components.items) |*list| {
        list.deinit(gpa);
    }
    self.components.deinit(gpa);
    self.add_type_edges.deinit(gpa);
    self.remove_type_edges.deinit(gpa);
}

pub fn clearAndFree(self: *Archetype, gpa: std.mem.Allocator) void {
    for (self.components.items) |*list| {
        list.clearAndFree(gpa);
    }
    self.last_modified.deinit(gpa);
    self.entities.clearAndFree(gpa);
}

pub fn addEntity(self: *Archetype, gpa: std.mem.Allocator, entity: Entity) !void {
    try self.entities.append(gpa, entity);
    for (self.components.items) |*list| {
        try list.appendEmpty(gpa);
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

pub fn removeEntity(self: *Archetype, gpa: std.mem.Allocator, entity: Entity) void {
    const index = self.findEntity(entity) orelse return;

    for (self.components.items) |*component| {
        component.deinitComponent(gpa, index);
        component.swapRemove(index);
    }
    _ = self.entities.swapRemove(index);
}

pub fn moveEntity(self: *Archetype, gpa: std.mem.Allocator, dst: *Archetype, entity: Entity) !usize {
    const eid = self.findEntity(entity).?;
    try dst.entities.append(gpa, entity);

    for (dst.components.items) |*component| {
        const cid = self.getTypeIdLocation(component.desc.id);
        if (cid) |i| {
            try component.appendRaw(gpa, self.components.items[i].getSingleRaw(eid));
        } else {
            try component.appendEmpty(gpa);
        }
    }
    for (self.components.items) |*component| {
        component.swapRemove(eid);
    }
    _ = self.entities.swapRemove(eid);
    return dst.entities.items.len - 1;
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

pub fn markComponentModified(self: *Archetype, comptime T: type, frame: Frame) void {
    const index = self.getTypeLocation(T) orelse return;
    self.last_modified.items[index] = frame;
}

pub fn markAllModified(self: *Archetype, frame: Frame) void {
    for (&self.last_modified) |*last| {
        last = frame;
    }
}

pub fn getLastModified(self: *const Archetype, comptime T: type) ?Frame {
    const index = self.getTypeLocation(T) orelse return null;
    return self.last_modified.items[index];
}

/// Adds another component to the current archetype. The newly allocated components are not initialized
pub fn expand(self: *Archetype, gpa: std.mem.Allocator, comptime T: type) !void {
    var new_list = ComponentList.init(.get(T));
    try new_list.allocate(gpa, T, self.entities.items.len);
    for (self.components.items, 0..) |c, i| {
        if (@intFromPtr(c.desc.id) > @intFromPtr(new_list.desc.id)) {
            try self.components.insert(gpa, i, new_list);
            return;
        }
    }
    try self.components.append(gpa, new_list);
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

    archetype.removeEntity(gpa, e2);

    try testing.expectEqual(@as(usize, 2), archetype.count());
    try testing.expect(archetype.findEntity(e2) == null);

    for (archetype.components.items) |list| {
        try testing.expectEqual(@as(usize, 2), list.count());
    }

    archetype.removeEntity(gpa, e2);
    try testing.expectEqual(@as(usize, 2), archetype.count());
    for (archetype.components.items) |list| {
        try testing.expectEqual(@as(usize, 2), list.count());
    }
}
