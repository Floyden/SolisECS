const std = @import("std");
const _component = @import("components.zig");
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

entities: ArrayList(Entity),
components: ArrayList(ComponentList),

addTypeEdges: ArrayList(Edge),
removeTypeEdges: ArrayList(Edge),

fn typeLt(_: void, a: ComponentList, b: ComponentList) bool {
    return @intFromPtr(a.desc.name.ptr) < @intFromPtr(b.desc.name.ptr);
}

pub fn init(allocator: std.mem.Allocator, components: []ComponentDesc) !Archetype {
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
    self.removeTypeEdges.deinit(allocator);
    self.addTypeEdges.deinit(allocator);
}

pub fn addEntity(self: *Archetype, entity: Entity) !void {
    try self.entities.append(entity);
    for (self.components.items) |*list| {
        try list.append(void, {});
    }
}

pub fn hasEntity(self: *const Archetype, entity: Entity) ?usize {
    for (self.entities.items, 0..) |candidate, i| {
        if (candidate.id == entity.id) {
            return i;
        }
    }
    return null;
}

pub fn removeEntity(self: *Archetype, entity: Entity) void {
    const index = self.hasEntity(entity);
    if (index == null) return;

    for (self.components.items) |*component| {
        component.swapDelete(index.?);
    }
    _ = self.entities.swapRemove(index.?);
}

pub fn getTypeLocation(self: *const Archetype, t: [:0]const u8) ?usize {
    for (self.components.items, 0..) |c, i| {
        if (@intFromPtr(c.desc.name.ptr) == @intFromPtr(t.ptr)) {
            return i;
        }
    }
    return null;
}

pub fn hasType(self: *const Archetype, t: [:0]const u8) bool {
    return self.getTypeLocation(t) != null;
}

pub fn count(self: *const Archetype) usize {
    return self.entities.items.len;
}
