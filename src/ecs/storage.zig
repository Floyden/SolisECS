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
    allocator: Allocator,
    // data: *anyopaque,
    // elements: usize,
    // capacity: usize,

    pub fn init(allocator: Allocator, desc: ComponentDesc) ComponentList {
        return ComponentList{ .allocator = allocator, .desc = desc };
    }

    pub fn append(self: *ComponentList) !void {
        _ = self;
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
        self.types.deinit();
        self.components.deinit();
        self.removeTypeEdges.deinit();
        self.addTypeEdges.deinit();
    }

    pub fn addEntity(self: *Archetype, entity: ecs.Entity) !void {
        try self.entities.append(entity);
        for (0..self.components.items.len) |i| {
            try self.components.items[i].append();
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

    pub fn setComponents(self: *Storage, entity: ecs.Entity, comptime T: type, arg: T) !void {
        _ = arg;
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
                // _ = source.?.components.items[j].swapRemove(entityIdx);
                // try destination.?.components.append(source.?.components.items[i]);
                i += 1;
            } else {
                try destination.?.components.items[j].append();
            }
            j += 1;
        }
    }
};
