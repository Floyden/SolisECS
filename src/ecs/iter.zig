const std = @import("std");
const ecs = @import("ecs.zig");
const storage = @import("storage.zig");
const World = ecs.World;
const Archetype = storage.Archetype;
const ComponentList = storage.ComponentList;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
