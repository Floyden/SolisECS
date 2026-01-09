const std = @import("std");
const ecs = @import("solis_ecs");
const Entity = ecs.Entity;

pub const Pair = struct {
    src: Entity,
    dst: Entity,
    relation: ecs.TypeId,
};

const PairUntyped = struct {
    src: Entity,
    dst: Entity,
};

pub const Storage = struct {
    pub const empty: Storage = .{
        .relations = .empty,
    };

    // TODO: use multiple maps for fast access of pairs
    relations: std.AutoArrayHashMapUnmanaged(ecs.TypeId, std.ArrayList(PairUntyped)),

    pub fn deinit(self: *Storage, gpa: std.mem.Allocator) void {
        const vals = self.relations.values();
        for (vals) |*value| {
            value.deinit(gpa);
        }
        self.relations.deinit(gpa);
    }

    pub fn add(self: *Storage, gpa: std.mem.Allocator, pair: Pair) !void {
        const list = try self.relations.getOrPutValue(gpa, pair.relation, .empty);
        try list.value_ptr.append(gpa, .{ .src = pair.src, .dst = pair.dst });
    }

    pub fn remove(self: *Storage, pair: Pair) void {
        const list = self.relations.getPtr(pair.relation) orelse return;
        for (list.items, 0..) |item, i| {
            if (item.src.id == pair.src.id and item.dst.id == pair.dst.id) {
                _ = list.swapRemove(i);
                return;
            }
        }
    }

    pub fn contains(self: *const Storage, pair: Pair) bool {
        const list = self.relations.get(pair.relation) orelse return false;
        for (list.items) |item| {
            const src_match = pair.src.id == Entity.any.id or item.src.id == pair.src.id;
            const dst_match = pair.dst.id == Entity.any.id or item.dst.id == pair.dst.id;
            if (src_match and dst_match)
                return true;
        }
        return false;
    }
};
