const std = @import("std");
const ecs = @import("ecs.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ComponentList = struct {
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

    pub fn init(allocator: Allocator, comptime types: anytype) !Archetype {
        var typeVec = ArrayList([:0]const u8).init(allocator);
        var componentVec = ArrayList(ComponentList).init(allocator);
        const ArgsType = @TypeOf(types);
        const args_type_info = @typeInfo(ArgsType);

        const field_info = args_type_info.Struct.fields;
        inline for (0..field_info.len) |i| {
            const name = @typeName(@field(types, field_info[i].name));
            try typeVec.append(name);
            try componentVec.append(ComponentList{});
        }

        // Number of elements should be rather small, perfect for insertion sort
        std.sort.insertion([:0]const u8, typeVec.items, {}, typeLt);

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

    pub fn hasEntity(self: *const Archetype, entity: ecs.Entity) bool {
        for (self.entities.items) |candidate| {
            if (candidate == entity) {
                return true;
            }
        }
        return false;
    }
};

pub const Storage = struct {
    allocator: Allocator,
    archetypes: ArrayList(Archetype),

    pub fn init(allocator: Allocator) !Storage {
        var archetypes = ArrayList(Archetype).init(allocator);
        try archetypes.append(try Archetype.init(allocator, .{})); // Create Archetype for empty entities
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

    pub fn setComponents(self: *Storage, entity: ecs.Entity, comptime T: type, arg: T) void {
        // Find Archetype of the Entity
        var source: *Archetype = undefined;
        for (self.archetypes.items) |archetype| {
            if (archetype.hasEntity(entity)) {
                source = &archetype;
                break;
            }
        }
        std.debug.assert(source != undefined);

        // Find new destination
        var destination = undefined;
        for (source.addTypeEdges.items) |edge| {
            if (edge.typeName == @typeName(T)) {
                destination = edge.to;
                break;
            }
        }

        // Create new Archetype if the destination is not found
        if (destination == undefined) {
            self.archetypes.append(Archetype.init(self.allocator, .{}));
        }

        _ = arg;
    }
};
