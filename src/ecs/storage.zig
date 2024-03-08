const std = @import("std");
const ecs = @import("ecs.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ComponentList = struct {};

const Archetype = struct {
    entities: ArrayList(ecs.Entity),
    types: ArrayList([:0]const u8),
    components: ArrayList(ComponentList),

    fn typeLt(ctx: void, a: [:0]const u8, b: [:0]const u8) bool {
        _ = ctx;
        return @intFromPtr(a.ptr) < @intFromPtr(b.ptr);
    }

    pub fn init(allocator: Allocator, comptime types: anytype) !Archetype {
        var typeVec = ArrayList([:0]const u8).init(allocator);
        const ArgsType = @TypeOf(types);
        const args_type_info = @typeInfo(ArgsType);

        const field_info = args_type_info.Struct.fields;
        inline for (0..field_info.len) |i| {
            const name = @typeName(@field(types, field_info[i].name));
            try typeVec.append(name);
        }

        // Number of elements should be rather small, perfect for insertion sort
        std.sort.insertion([:0]const u8, typeVec.items, {}, typeLt);

        return Archetype{
            .entities = ArrayList(ecs.Entity).init(allocator),
            .types = typeVec,
            .components = ArrayList(ComponentList).init(allocator),
        };
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit();
        self.types.deinit();
        self.components.deinit();
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
        _ = self;
        return entity;
    }

    pub fn markEntity(self: *Storage, entity: ecs.Entity) void {
        _ = entity;
        _ = self;
    }

    pub fn removeMarked(self: *Storage) void {
        _ = self;
    }

    pub fn setComponents(self: *Storage, entity: ecs.Entity, comptime args: anytype) void {
        _ = args;
        _ = entity;
        _ = self;
    }
};
