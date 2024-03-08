const std = @import("std");
const ecs = @import("ecs.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const TypeId = struct {
    name: [:0]const u8,
};

fn GetTypeId(comptime T: type) TypeId {
    return TypeId{ .name = @typeName(T) };
}

const ComponentList = struct {
    // allocator: Allocator,
    // data: *anyopaque,
    // elements: usize,
    // capacity: usize,
    //
    // pub fn init(allocator: Allocator, comptime T: type) ComponentList {
    //     return ComponentList{ .allocator = allocator, .data = allocator.alloc(T, 16), .elements = 0, .capacity = 16 };
    // }

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
    types: ArrayList([:0]const u8),
    components: ArrayList(ComponentList),

    addTypeEdges: ArrayList(ArchetypeEdge),
    removeTypeEdges: ArrayList(ArchetypeEdge),

    fn typeLt(ctx: void, a: [:0]const u8, b: [:0]const u8) bool {
        _ = ctx;
        return @intFromPtr(a.ptr) < @intFromPtr(b.ptr);
    }

    pub fn init(allocator: Allocator, typeNames: [][:0]const u8) !Archetype {
        var typeVec = ArrayList([:0]const u8).init(allocator);
        var componentVec = ArrayList(ComponentList).init(allocator);

        for (0..typeNames.len) |i| {
            try typeVec.append(typeNames[i]);
            try componentVec.append(ComponentList{});
        }

        // Number of elements should be rather small, perfect for insertion sort
        std.sort.insertion([:0]const u8, typeVec.items, {}, typeLt);

        std.debug.print("{s}\n", .{typeVec.items});

        return Archetype{
            .entities = ArrayList(ecs.Entity).init(allocator),
            .types = typeVec,
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
            var types = try self.allocator.alloc([:0]const u8, source.?.types.items.len + 1);
            defer self.allocator.free(types);
            std.mem.copyForwards([:0]const u8, types, source.?.types.items);
            types[source.?.types.items.len] = @typeName(T);

            try self.archetypes.append(try Archetype.init(self.allocator, types));
            var dest = &self.archetypes.items[self.archetypes.items.len - 1];
            try dest.removeTypeEdges.append(ArchetypeEdge{ .from = dest, .to = source.?, .typeName = @typeName(T) });
            try source.?.addTypeEdges.append(ArchetypeEdge{ .from = source.?, .to = dest, .typeName = @typeName(T) });
            destination = dest;
        }

        // Move entity
        try destination.?.entities.append(source.?.entities.items[entityIdx]);
        var i: usize = 0;
        var j: usize = 0;
        while (j < destination.?.types.items.len) {
            if (@intFromPtr(destination.?.types.items[j].ptr) != @intFromPtr(@typeName(T))) {
                // _ = source.?.components.items[j].swapRemove(entityIdx);
                // try destination.?.components.append(source.?.components.items[i]);
                i += 1;
            } else {
                try destination.?.components.items[j].append(); //arg);
            }
            j += 1;
        }

        _ = source.?.entities.swapRemove(entityIdx);
    }
};
