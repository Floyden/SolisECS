const std = @import("std");
const ecs = @import("ecs.zig");
const storage = @import("storage.zig");
const World = ecs.World;
const Archetype = storage.Archetype;
const ComponentList = storage.ComponentList;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const ComponentTuple = struct {
    elements: []*anyopaque,
    index: usize,

    pub fn getMut(self: *const ComponentTuple, comptime T: type, loc: usize) *T {
        return @as(*ComponentList, @alignCast(@ptrCast(self.elements[loc]))).getMut(T, self.index).?;
    }

    pub fn get(self: *const ComponentTuple, comptime T: type, loc: usize) *const T {
        return @as(*ComponentList, @alignCast(@ptrCast(self.elements[loc]))).get(T, self.index).?;
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

        return Iter{ .world = world, .archetype = archetype, .types = types, .currentIndex = 0, .componentPtrs = componentPtrs };
    }

    pub fn deinit(self: Iter) void {
        self.componentPtrs.deinit();
    }

    pub fn next(self: *Iter) ?ComponentTuple {
        if (self.currentIndex >= self.archetype.count()) {
            return null;
        }

        for (0..self.types.len) |i| {
            const typeIndex = self.types[i];
            var index = self.archetype.getTypeLocation(typeIndex);
            if (index == null) {
                std.debug.print("Unexpected end of iterator", .{});
                return null;
            }
            index = index.?;
            self.componentPtrs.items[i] = &self.archetype.components.items[index.?];
        }

        defer self.currentIndex += 1; // Update index after setting it in the tuple
        return ComponentTuple{ .elements = self.componentPtrs.items, .index = self.currentIndex };
    }
};
