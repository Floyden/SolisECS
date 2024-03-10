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

const ComponentList = struct {
    desc: ComponentDesc,
    data: ArrayList(u8),

    pub fn init(allocator: Allocator, desc: ComponentDesc) ComponentList {
        return ComponentList{ .desc = desc, .data = ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *ComponentList) void {
        self.data.deinit();
    }

    pub fn append(self: *ComponentList, comptime T: type, component: T) !void {
        const data: [*]const u8 = @ptrCast(&component);
        try self.data.appendSlice(data[0..@sizeOf(T)]);
    }

    pub fn appendRaw(self: *ComponentList, component: []u8) !void {
        try self.data.appendSlice(component);
    }

    fn swapRemoveRaw(self: *ComponentList, index: usize, dest: *[]u8) void {
        const typeSize = self.desc.size;
        var i = typeSize;
        while (i > 0) {
            dest.*[i - 1] = self.data.swapRemove(index * typeSize + i - 1);
            i -= 1;
        }
    }

    pub fn get(self: *ComponentList, comptime T: type, index: usize) ?*const T {
        const typeSize = self.desc.size;
        const data = self.data.items.ptr + index * typeSize;
        return @as(*const T, @alignCast(@ptrCast(data)));
    }

    pub fn getMut(self: *ComponentList, comptime T: type, index: usize) ?*T {
        const typeSize = self.desc.size;
        const data = self.data.items.ptr + index * typeSize;
        return @as(*T, @alignCast(@ptrCast(data)));
    }
};

const ArchetypeEdge = struct {
    from: *Archetype,
    to: *Archetype,
    typeName: [:0]const u8,
};

const Archetype = struct {
    entities: ArrayList(ecs.Entity),
    components: ArrayList(ComponentList),

    addTypeEdges: ArrayList(ArchetypeEdge),
    removeTypeEdges: ArrayList(ArchetypeEdge),

    fn typeLt(ctx: void, a: ComponentList, b: ComponentList) bool {
        _ = ctx;
        return @intFromPtr(a.desc.name.ptr) < @intFromPtr(b.desc.name.ptr);
    }

    pub fn init(allocator: Allocator, components: []ComponentDesc) !Archetype {
        var componentVec = ArrayList(ComponentList).init(allocator);

        for (components) |component| {
            try componentVec.append(ComponentList.init(allocator, component));
        }

        // Number of elements should be rather small, perfect for insertion sort
        std.sort.insertion(ComponentList, componentVec.items, {}, typeLt);

        return Archetype{
            .entities = ArrayList(ecs.Entity).init(allocator),
            .components = componentVec,
            .addTypeEdges = ArrayList(ArchetypeEdge).init(allocator),
            .removeTypeEdges = ArrayList(ArchetypeEdge).init(allocator),
        };
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();
        for (self.components.items) |*list| {
            list.deinit();
        }
        self.components.deinit();
        self.removeTypeEdges.deinit();
        self.addTypeEdges.deinit();
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
};

pub const Storage = struct {
    allocator: Allocator,
    archetypes: ArrayList(Archetype),

    pub fn init(allocator: Allocator) !Storage {
        var archetypes = ArrayList(Archetype).init(allocator);
        try archetypes.append(try Archetype.init(allocator, &.{})); // Create Archetype for empty entities
        return Storage{ .allocator = allocator, .archetypes = archetypes };
    }

    pub fn deinit(self: *Storage) void {
        for (self.archetypes.items) |*list| {
            list.deinit();
        }
        self.archetypes.deinit();
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
                return list.get(T, index);
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
        var entityIdx: usize = undefined;
        var source: ?*Archetype = null;
        for (0..self.archetypes.items.len) |i| {
            if (self.archetypes.items[i].hasEntity(entity)) |value| {
                entityIdx = value;
                source = &self.archetypes.items[i];
                break;
            }
        }
        // Entity was not found
        std.debug.assert(source != null);

        // Find new destination
        var destination: ?*Archetype = null;
        for (source.?.addTypeEdges.items) |edge| {
            if (@intFromPtr(edge.typeName.ptr) == @intFromPtr(@typeName(T))) {
                destination = edge.to;
                break;
            }
        }

        // Create new Archetype if the destination is not found
        if (destination == null) {
            var types = try self.allocator.alloc(ComponentDesc, source.?.components.items.len + 1);
            defer self.allocator.free(types);
            for (source.?.components.items, 0..) |list, i| {
                types.ptr[i] = list.desc;
            }
            types[source.?.components.items.len] = ComponentDesc{ .size = @sizeOf(T), .alignment = @alignOf(T), .name = @typeName(T) };

            try self.archetypes.append(try Archetype.init(self.allocator, types));
            var dest = &self.archetypes.items[self.archetypes.items.len - 1];
            try dest.removeTypeEdges.append(ArchetypeEdge{ .from = dest, .to = source.?, .typeName = @typeName(T) });
            try source.?.addTypeEdges.append(ArchetypeEdge{ .from = source.?, .to = dest, .typeName = @typeName(T) });
            destination = dest;
        }

        // Move entity
        try destination.?.entities.append(source.?.entities.swapRemove(entityIdx));

        var i: usize = 0;
        var j: usize = 0;
        while (j < destination.?.components.items.len) {
            if (@intFromPtr(destination.?.components.items[j].desc.name.ptr) != @intFromPtr(@typeName(T))) {
                var data = try self.allocator.alloc(u8, source.?.components.items[i].desc.size);
                defer self.allocator.free(data);
                source.?.components.items[i].swapRemoveRaw(entityIdx, &data);
                try destination.?.components.items[j].appendRaw(data);

                i += 1;
            } else {
                try destination.?.components.items[j].append(T, arg);
            }
            j += 1;
        }
    }
};
