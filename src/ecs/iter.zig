const std = @import("std");
const ecs = @import("ecs.zig");
const storage = @import("storage.zig");
const World = ecs.World;
const Archetype = storage.Archetype;
const ComponentList = storage.ComponentList;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Query = struct {
    world: *World,
    archetypes: ArrayList(*Archetype),
    pointers: ArrayList(ArrayList(*anyopaque)),
    types: ArrayList([:0]const u8),

    pub fn init(allocator: Allocator, world: *World, types: [][:0]const u8) !Query {
        var typeArray = ArrayList([:0]const u8).init(allocator);
        for (types) |t| {
            try typeArray.append(t);
        }
        return Query{ .world = world, .archetypes = ArrayList(*Archetype).init(allocator), .pointers = ArrayList(ArrayList(*anyopaque)).init(allocator), .types = typeArray };
    }

    pub fn addArchetype(self: *Query, archetype: *Archetype) !void {
        try self.archetypes.append(archetype);
        try self.pointers.append(ArrayList(*anyopaque).init(self.pointers.allocator));
        var back = &self.pointers.items[self.pointers.items.len - 1];
        try back.resize(self.types.items.len);
        for (0..self.types.items.len) |i| {
            const typeIndex = self.types.items[i];
            const index = archetype.getTypeLocation(typeIndex).?;
            back.items[i] = &archetype.components.items[index];
        }
    }

    pub fn iter(self: *Query, index: usize) !Iter {
        return Iter.init(self.archetypes.allocator, self.world, self.archetypes.items[index], self.types.items);
    }
};

pub const Iter = struct {
    world: *World,
    archetype: *Archetype,
    types: [][:0]const u8,
    currentIndex: usize,

    componentPtrs: ArrayList(*anyopaque),

    pub fn init(allocator: Allocator, world: *World, archetype: *Archetype, types: [][:0]const u8) !Iter {
        var componentPtrs = ArrayList(*anyopaque).init(allocator);
        try componentPtrs.resize(types.len);
        for (0..types.len) |i| {
            const typeIndex = types[i];
            const index = archetype.getTypeLocation(typeIndex).?;
            componentPtrs.items[i] = &archetype.components.items[index];
        }

        return Iter{ .world = world, .archetype = archetype, .types = types, .currentIndex = 0, .componentPtrs = componentPtrs };
    }

    pub fn deinit(self: Iter) void {
        self.componentPtrs.deinit();
    }

    pub fn getMut(self: *const Iter, comptime T: type, loc: usize) []T {
        return @as(*ComponentList, @alignCast(@ptrCast(self.componentPtrs.items[loc]))).getMut(T);
    }

    pub fn get(self: *const Iter, comptime T: type, loc: usize) []const T {
        return @as(*ComponentList, @alignCast(@ptrCast(self.componentPtrs.items[loc]))).get(T);
    }
};
