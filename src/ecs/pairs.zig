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

const TraverseDesc = struct {
    relation: ecs.TypeId,
    node: Entity,
    bfs: bool = true, // true: use bfs; false: use dfs
    reversed: bool = false,
};

pub const Storage = struct {
    // TODO: use multiple maps for fast access of pairs
    relations: std.AutoArrayHashMapUnmanaged(ecs.TypeId, std.ArrayList(PairUntyped)),

    pub const empty: Storage = .{
        .relations = .empty,
    };

    pub const Iterator = struct {
        pairs: *const std.ArrayList(PairUntyped),
        index: usize,
        query: Pair,

        pub fn next(it: *Iterator) ?PairUntyped {
            for (it.pairs.items[it.index..], it.index..) |pair, i| {
                const src_match = it.query.src.id == Entity.any.id or it.query.src.id == pair.src.id;
                const dst_match = it.query.dst.id == Entity.any.id or it.query.dst.id == pair.dst.id;
                if (src_match and dst_match) {
                    it.index = i + 1;
                    return pair;
                }
            }
            it.index = it.pairs.items.len;
            return null;
        }
    };

    pub const TraverseIter = struct {
        desc: TraverseDesc,
        gpa: std.mem.Allocator,
        storage: *const Storage,
        queue: std.ArrayList(Entity),
        found: std.AutoArrayHashMapUnmanaged(Entity, void),
        next_idx: usize,

        pub fn init(gpa: std.mem.Allocator, storage: *const Storage, desc: TraverseDesc) !TraverseIter {
            var res = TraverseIter{
                .desc = desc,
                .gpa = gpa,
                .storage = storage,
                .queue = .empty,
                .found = .empty,
                .next_idx = 0,
            };

            try res.queue.append(gpa, desc.node);
            try res.found.put(gpa, desc.node, {});
            return res;
        }

        pub fn next(self: *TraverseIter) !?Entity {
            if (self.next_idx >= self.queue.items.len) return null;
            if (!self.desc.bfs) @panic("Not Implemented");
            const query: Pair = if (!self.desc.reversed) .{
                .src = self.queue.items[self.next_idx],
                .relation = self.desc.relation,
                .dst = .any,
            } else .{
                .src = .any,
                .relation = self.desc.relation,
                .dst = self.queue.items[self.next_idx],
            };

            var matches = self.storage.match(query);
            while (matches.next()) |edge| {
                const node = if (!self.desc.reversed) edge.dst else edge.src;
                const res = try self.found.getOrPut(self.gpa, node);
                if (!res.found_existing)
                    try self.queue.append(self.gpa, node);
            }
            defer self.next_idx += 1;
            return self.queue.items[self.next_idx];
        }

        pub fn deinit(self: *TraverseIter) void {
            self.queue.deinit(self.gpa);
            self.found.deinit(self.gpa);
        }
    };

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

    // Find all pairs which fit the filter pair.
    pub fn match(self: *const Storage, filter: Pair) Iterator {
        const list = self.relations.getPtr(filter.relation) orelse return Iterator{
            .pairs = &std.ArrayList(PairUntyped).empty,
            .index = 0,
            .query = filter,
        };
        return Iterator{
            .pairs = list,
            .index = 0,
            .query = filter,
        };
    }

    pub fn traverse(self: *const Storage, gpa: std.mem.Allocator, desc: TraverseDesc) !TraverseIter {
        return try TraverseIter.init(gpa, self, desc);
    }
};

const TestRel = struct {};
const TestRel2 = struct {};

test "Add/Remove Pair" {
    const gpa = std.testing.allocator;
    var storage = Storage.empty;
    defer storage.deinit(gpa);

    const pair = Pair{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 2 },
    };

    const pair2 = Pair{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 3 },
        .dst = .{ .id = 4 },
    };

    try std.testing.expect(!storage.contains(pair));
    try std.testing.expect(!storage.contains(pair2));
    try storage.add(gpa, pair);
    try storage.add(gpa, pair2);
    try std.testing.expect(storage.contains(pair));
    try std.testing.expect(storage.contains(pair2));
    storage.remove(pair);
    try std.testing.expect(!storage.contains(pair));
    try std.testing.expect(storage.contains(pair2));
}

test "Any query" {
    const gpa = std.testing.allocator;
    var storage = Storage.empty;
    defer storage.deinit(gpa);

    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 2 },
    });

    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 3 },
        .dst = .{ .id = 4 },
    });

    const query1 = Pair{
        .relation = ecs.typeId(TestRel),
        .src = Entity.any,
        .dst = .{ .id = 2 },
    };

    const query2 = Pair{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = Entity.any,
    };

    const query3 = Pair{
        .relation = ecs.typeId(TestRel),
        .src = Entity.any,
        .dst = Entity.any,
    };

    try std.testing.expect(storage.contains(query1));
    try std.testing.expect(storage.contains(query2));
    try std.testing.expect(storage.contains(query3));
}

test "query respects relations" {
    const gpa = std.testing.allocator;
    var storage = Storage.empty;
    defer storage.deinit(gpa);

    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 2 },
    });

    const query = Pair{
        .relation = ecs.typeId(TestRel2),
        .src = Entity.any,
        .dst = Entity.any,
    };

    try std.testing.expect(!storage.contains(query));
}

test "Match test" {
    const gpa = std.testing.allocator;
    var storage = Storage.empty;
    defer storage.deinit(gpa);

    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 10 },
    });
    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 2 },
        .dst = .{ .id = 10 },
    });
    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 3 },
        .dst = .{ .id = 20 },
    });

    var it = storage.match(.{
        .relation = ecs.typeId(TestRel),
        .src = Entity.any,
        .dst = .{ .id = 10 },
    });

    const first = it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 10), first.dst.id);
    const second = it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 10), second.dst.id);
    try std.testing.expect(it.next() == null);
}

test "Traverse test" {
    const gpa = std.testing.allocator;
    var storage = Storage.empty;
    defer storage.deinit(gpa);

    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 10 },
    });
    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 2 },
        .dst = .{ .id = 10 },
    });
    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 1 },
        .dst = .{ .id = 20 },
    });
    try storage.add(gpa, .{
        .relation = ecs.typeId(TestRel),
        .src = .{ .id = 3 },
        .dst = .{ .id = 20 },
    });

    var it = try storage.traverse(gpa, .{
        .relation = ecs.typeId(TestRel),
        .node = .{ .id = 1 },
    });

    var e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 1), e.id);
    e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 10), e.id);
    e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 20), e.id);
    try std.testing.expectEqual(try it.next(), null);
    it.deinit();

    it = try storage.traverse(gpa, .{
        .relation = ecs.typeId(TestRel),
        .node = .{ .id = 20 },
        .reversed = true,
    });

    e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 20), e.id);
    e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 1), e.id);
    e = try it.next() orelse return error.TestUnexpectedNull;
    try std.testing.expectEqual(@as(u32, 3), e.id);
    try std.testing.expectEqual(try it.next(), null);
    it.deinit();
}
