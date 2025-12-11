const std = @import("std");
const ecs = @import("ecs.zig");
const _component = @import("components.zig");
pub const Archetype = @import("Archetype.zig");
const ComponentDesc = _component.Description;
const ComponentList = _component.List;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Storage = @This();

allocator: Allocator,
archetypes: ArrayList(Archetype),

pub fn init(allocator: Allocator) !Storage {
    var archetypes: ArrayList(Archetype) = .empty;
    try archetypes.append(allocator, try Archetype.init(allocator, &.{})); // Create Archetype for empty entities
    return Storage{ .allocator = allocator, .archetypes = archetypes };
}

pub fn deinit(self: *Storage) void {
    for (self.archetypes.items) |*list| {
        list.deinit(self.allocator);
    }
    self.archetypes.deinit(self.allocator);
}

pub fn addEntity(self: *Storage, entity: ecs.Entity) !ecs.Entity {
    // Store entity in Archetype without components
    try self.archetypes.items[0].addEntity(entity);
    return entity;
}

pub fn markEntity(self: *Storage, entity: ecs.Entity) void {
    _ = entity;
    _ = self;
}

pub fn removeMarked(self: *Storage) void {
    _ = self;
}

fn findArchetype(self: *Storage, entity: ecs.Entity) ?struct { index: usize, archetype: *Archetype } {
    for (0..self.archetypes.items.len) |i| {
        if (self.archetypes.items[i].hasEntity(entity)) |value| {
            return .{ .index = value, .archetype = &self.archetypes.items[i] };
        }
    }
    return null;
}

pub fn get(self: *Storage, comptime T: type, entity: ecs.Entity) ?*const T {
    const location = self.findArchetype(entity).?;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (@intFromPtr(list.desc.name.ptr) == @intFromPtr(@typeName(T))) {
            return &list.get(T)[index];
        }
    }
    return null;
}

pub fn getMut(self: *Storage, comptime T: type, entity: ecs.Entity) ?*T {
    const location = self.findArchetype(entity).?;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (@intFromPtr(list.desc.name.ptr) == @intFromPtr(@typeName(T))) {
            return list.getMut(T, index);
        }
    }
    return null;
}

pub fn setComponents(self: *Storage, entity: ecs.Entity, comptime T: type, arg: T) !void {
    // Find Archetype of the Entity
    const location = self.findArchetype(entity);
    std.debug.assert(location != null);

    const entityIdx = location.?.index;
    var source = location.?.archetype;

    // Find new destination
    var destination: ?*Archetype = null;
    for (source.addTypeEdges.items) |edge| {
        if (@intFromPtr(edge.typeName.ptr) == @intFromPtr(@typeName(T))) {
            destination = edge.to;
            break;
        }
    }

    // Create new Archetype if the destination is not found
    if (destination == null) {
        var types = try self.allocator.alloc(ComponentDesc, source.components.items.len + 1);
        defer self.allocator.free(types);
        for (source.components.items, 0..) |list, i| {
            types.ptr[i] = list.desc;
        }
        types[source.components.items.len] = ComponentDesc{ .size = @sizeOf(T), .alignment = @alignOf(T), .name = @typeName(T) };

        try self.archetypes.append(try Archetype.init(self.allocator, types));
        var dest = &self.archetypes.items[self.archetypes.items.len - 1];
        try dest.removeTypeEdges.append(Archetype.Edge{ .from = dest, .to = source, .typeName = @typeName(T) });
        try source.addTypeEdges.append(Archetype.Edge{ .from = source, .to = dest, .typeName = @typeName(T) });
        destination = dest;
    }

    // Move entity
    try destination.?.entities.append(entity);

    for (destination.?.components.items) |*component| {
        const index = source.getTypeLocation(component.desc.name);
        if (index == null) {
            try component.append(T, arg);
            continue;
        }
        try component.appendRaw(source.components.items[index.?].getSingleRaw(entityIdx));
    }
    source.removeEntity(entity);
}
