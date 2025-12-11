const std = @import("std");
const ecs = @import("ecs.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ComponentDesc = ecs.ComponentDesc;

const TypeId = struct {
    name: [:0]const u8,
};

fn GetTypeId(comptime T: type) TypeId {
    return TypeId{ .name = @typeName(T) };
}

pub const ComponentList = struct {
    desc: ComponentDesc,
    data: ArrayList(usize),

    pub fn init(desc: ComponentDesc) ComponentList {
        return ComponentList{ .desc = desc, .data = .empty };
    }

    pub fn deinit(self: *ComponentList, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn append(self: *ComponentList, comptime T: type, component: T) !void {
        const data: [*]const usize = @ptrCast(@alignCast(&component));
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        try self.data.appendSlice(data[0..size]);
    }

    pub fn appendRaw(self: *ComponentList, component: []const usize) !void {
        try self.data.appendSlice(component);
    }

    fn swapRemoveRaw(self: *ComponentList, index: usize, dest: *[]usize) void {
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        var i = size;
        while (i > 0) {
            i -= 1;
            dest.*[i] = self.data.swapRemove(index * size + i);
        }
    }

    fn swapDelete(self: *ComponentList, index: usize) void {
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        var i = size;
        while (i > 0) {
            i -= 1;
            _ = self.data.swapRemove(index * size + i);
        }
    }

    pub fn get(self: *ComponentList, comptime T: type) []const T {
        const offset = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        const count = self.data.items.len / offset;
        return @as([*]const T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getMut(self: *ComponentList, comptime T: type) []T {
        const offset = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        const count = self.data.items.len / offset;
        return @as([*]T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getSingleRaw(self: *ComponentList, index: usize) []const usize {
        return @as([*]usize, @ptrCast(@alignCast(self.data.items.ptr)))[index .. index + 1];
    }
};

const ArchetypeEdge = struct {
    from: *Archetype,
    to: *Archetype,
    typeName: [:0]const u8,
};

pub const Archetype = struct {
    entities: ArrayList(ecs.Entity),
    components: ArrayList(ComponentList),

    addTypeEdges: ArrayList(ArchetypeEdge),
    removeTypeEdges: ArrayList(ArchetypeEdge),

    fn typeLt(_: void, a: ComponentList, b: ComponentList) bool {
        return @intFromPtr(a.desc.name.ptr) < @intFromPtr(b.desc.name.ptr);
    }

    pub fn init(allocator: Allocator, components: []ComponentDesc) !Archetype {
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

    pub fn addEntity(self: *Archetype, entity: ecs.Entity) !void {
        try self.entities.append(entity);
        for (self.components.items) |*list| {
            try list.append(void, {});
        }
    }

    pub fn hasEntity(self: *const Archetype, entity: ecs.Entity) ?usize {
        for (self.entities.items, 0..) |candidate, i| {
            if (candidate.id == entity.id) {
                return i;
            }
        }
        return null;
    }

    pub fn removeEntity(self: *Archetype, entity: ecs.Entity) void {
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
};

pub const Storage = struct {
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
            try dest.removeTypeEdges.append(ArchetypeEdge{ .from = dest, .to = source, .typeName = @typeName(T) });
            try source.addTypeEdges.append(ArchetypeEdge{ .from = source, .to = dest, .typeName = @typeName(T) });
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
};
