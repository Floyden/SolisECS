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
    archetypes: ArrayList(*const Archetype),
    types: ArrayList([:0]const u8),
    currentArchetype: usize,
    currentIndex: usize,

    componentPtrs: ArrayList(*anyopaque),

    pub fn init(allocator: Allocator, world: *World, _types: [][:0]const u8) !Iter {
        var types = ArrayList([:0]const u8).init(allocator);
        for (_types) |t| {
            try types.append(t);
        }

        var archetypes = ArrayList(*const Archetype).init(allocator);
        outer: for (world.storage.archetypes.items) |*archetype| {
            for (types.items) |t| {
                if (!archetype.hasType(t)) continue :outer;
            }

            try archetypes.append(archetype);
        }
        var componentPtrs = ArrayList(*anyopaque).init(allocator);
        try componentPtrs.resize(types.items.len);

        return Iter{ .world = world, .archetypes = archetypes, .types = types, .currentArchetype = 0, .currentIndex = 0, .componentPtrs = componentPtrs };
    }

    pub fn deinit(self: Iter) void {
        self.componentPtrs.deinit();
        self.types.deinit();
        self.archetypes.deinit();
    }

    pub fn next(self: *Iter) ?ComponentTuple {
        if (self.archetypes.items.len == 0) return null;
        if (self.currentIndex >= self.archetypes.items[self.currentArchetype].count()) {
            self.currentIndex = 0;
            self.currentArchetype += 1;
        }
        if (self.currentArchetype >= self.archetypes.items.len) {
            return null;
        }

        const currentArchetype = self.archetypes.items[self.currentArchetype];
        for (0..self.types.items.len) |i| {
            const typeIndex = self.types.items[i];
            var index = currentArchetype.getTypeLocation(typeIndex);
            if (index == null) {
                std.debug.print("Unexpected end of iterator", .{});
                return null;
            }
            index = index.?;
            self.componentPtrs.items[i] = &currentArchetype.components.items[index.?];
        }

        defer self.currentIndex += 1; // Update index after setting it in the tuple
        return ComponentTuple{ .elements = self.componentPtrs.items, .index = self.currentIndex };
    }
};
