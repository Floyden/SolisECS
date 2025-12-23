const std = @import("std");
const Entity = @import("Entity.zig");
const _component = @import("components.zig");
const type_id = @import("type_id.zig");
pub const Archetype = @import("Archetype.zig");
const ComponentDesc = _component.Description;
const ComponentList = _component.List;
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
    const location = self.findArchetype(entity).?;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (list.desc.id == type_id.typeId(T)) {
            if (@sizeOf(T) == 0)
                return @ptrCast(list.get(T));
            return &list.get(T)[index];
        }
    }
    return null;
}

pub fn getMut(self: *const Storage, comptime T: type, entity: Entity) ?*T {
    const location = self.findArchetype(entity).?;
    const source = location.archetype;
    const index = location.index;

    for (source.components.items) |*list| {
        if (list.desc.id == type_id.typeId(T)) {
            if (@sizeOf(T) == 0)
                return @ptrCast(list.getMut(T));

            return &list.getMut(T)[index];
        }
    }
    return null;
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
        if (edge.id == type_id.typeId(T)) {
            destination = edge.to;
            break;
        }
    }

    // Create new Archetype if the destination is not found
    if (destination == null) {
        var types = try gpa.alloc(ComponentDesc, source.components.items.len + 1);
        defer gpa.free(types);
        for (source.components.items, 0..) |list, i| {
            types.ptr[i] = list.desc;
        }
        types[source.components.items.len] = ComponentDesc.get(T);

        const new_archetype = try gpa.create(Archetype);
        new_archetype.* = try Archetype.init(gpa, types);
        try self.archetypes.append(gpa, new_archetype);
        var dest = self.archetypes.items[self.archetypes.items.len - 1];
        try dest.removeTypeEdges.append(gpa, Archetype.Edge{ .from = dest, .to = source, .id = type_id.typeId(T) });
        try source.addTypeEdges.append(gpa, Archetype.Edge{ .from = source, .to = dest, .id = type_id.typeId(T) });
        destination = dest;
    }

    // Move entity
    try destination.?.entities.append(gpa, entity);

    for (destination.?.components.items) |*component| {
        const index = source.getTypeIdLocation(component.desc.id);
        if (index == null) {
            try component.append(gpa, T, arg);
            continue;
        }
        try component.appendRaw(gpa, source.components.items[index.?].getSingleRaw(entityIdx));
    }
    source.removeEntity(entity);
}
