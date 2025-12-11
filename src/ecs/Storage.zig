const std = @import("std");
const Entity = @import("Entity.zig");
const _component = @import("components.zig");
const type_id = @import("type_id.zig");
pub const Archetype = @import("Archetype.zig");
const ComponentDesc = _component.Description;
const ComponentList = _component.List;
const Allocator = std.mem.Allocator;

const Storage = @This();

allocator: Allocator,
// TODO: Figure out how to store stable pointers
archetypes: std.ArrayList(*Archetype),

pub fn init(allocator: Allocator) !Storage {
    var archetypes: std.ArrayList(*Archetype) = .empty;
    const empty_ptr = try allocator.create(Archetype);
    empty_ptr.* = Archetype.empty;

    try archetypes.append(allocator, empty_ptr); // Create Archetype for empty entities
    return Storage{ .allocator = allocator, .archetypes = archetypes };
}

pub fn deinit(self: *Storage) void {
    for (self.archetypes.items) |list| {
        list.deinit(self.allocator);
        self.allocator.destroy(list);
    }
    self.archetypes.deinit(self.allocator);
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

fn findArchetype(self: *Storage, entity: Entity) ?struct { index: usize, archetype: *Archetype } {
    for (0..self.archetypes.items.len) |i| {
        if (self.archetypes.items[i].findEntity(entity)) |value| {
            return .{ .index = value, .archetype = self.archetypes.items[i] };
        }
    }
    return null;
}

pub fn get(self: *Storage, comptime T: type, entity: Entity) ?*const T {
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

pub fn getMut(self: *Storage, comptime T: type, entity: Entity) ?*T {
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

pub fn setComponents(self: *Storage, entity: Entity, comptime T: type, arg: T) !void {
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
        types[source.components.items.len] = ComponentDesc.get(T);

        const new_archetype = try self.allocator.create(Archetype);
        new_archetype.* = try Archetype.init(self.allocator, types);
        try self.archetypes.append(self.allocator, new_archetype);
        var dest = self.archetypes.items[self.archetypes.items.len - 1];
        try dest.removeTypeEdges.append(self.allocator, Archetype.Edge{ .from = dest, .to = source, .typeName = @typeName(T) });
        try source.addTypeEdges.append(self.allocator, Archetype.Edge{ .from = source, .to = dest, .typeName = @typeName(T) });
        destination = dest;
    }

    // Move entity
    try destination.?.entities.append(self.allocator, entity);

    for (destination.?.components.items) |*component| {
        const index = source.getTypeLocation(component.desc.id);
        if (index == null) {
            try component.append(self.allocator, T, arg);
            continue;
        }
        try component.appendRaw(self.allocator, source.components.items[index.?].getSingleRaw(entityIdx));
    }
    source.removeEntity(entity);
}
