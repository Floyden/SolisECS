const std = @import("std");
const ecs = @import("solis_ecs");
const Entity = ecs.Entity;

pub const Pair = struct {
    src: Entity,
    dst: Entity,
    relation: ecs.TypeId,
};

pub const Storage = struct {
    pub const empty: Storage = .{ .pairs = .empty };

    // TODO: use multiple maps for fast access of pairs
    pairs: std.ArrayList(Pair),

    pub fn deinit(self: *Storage, gpa: std.mem.Allocator) void {
        self.pairs.deinit(gpa);
    }

    pub fn add(self: *Storage, gpa: std.mem.Allocator, pair: Pair) !void {
        try self.pairs.append(gpa, pair);
    }

    pub fn remove(self: *Storage, pair: Pair) void {
        for (self.pairs.items, 0..) |item, i| {
            if (std.meta.eql(item, pair)) {
                _ = self.pairs.swapRemove(i);
                return;
            }
        }
    }

    pub fn contains(self: *const Storage, pair: Pair) bool {
        for (self.pairs.items) |item| {
            if (std.meta.eql(item, pair)) {
                return true;
            }
        }
        return false;
    }
};
