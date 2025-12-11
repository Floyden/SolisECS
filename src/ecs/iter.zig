const std = @import("std");
const solis_ecs = @import("solis_ecs");
const ecs = @import("ecs.zig");
const Storage = @import("Storage.zig");
const World = solis_ecs.World;
const Archetype = @import("Archetype.zig");
const ComponentList = @import("components.zig").List;
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

    pub fn iter(self: *Query, index: usize) Iter {
        return Iter.init(self.world, self.archetypes.items[index], self.pointers.items[index].items);
    }
};

pub const Iter = struct {
    world: *World,
    archetype: *Archetype,
    components: []*anyopaque,

    pub fn init(world: *World, archetype: *Archetype, components: []*anyopaque) Iter {
        return Iter{ .world = world, .archetype = archetype, .components = components };
    }

    pub fn getMut(self: *const Iter, comptime T: type, loc: usize) []T {
        return @as(*ComponentList, @ptrCast(@alignCast(self.components[loc]))).getMut(T);
    }

    pub fn get(self: *const Iter, comptime T: type, loc: usize) []const T {
        return @as(*ComponentList, @ptrCast(@alignCast(self.components[loc]))).get(T);
    }
};
