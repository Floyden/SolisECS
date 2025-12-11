const std = @import("std");
const ArrayList = std.ArrayList;

pub const List = struct {
    desc: Description,
    data: ArrayList(u8),

    pub fn init(desc: Description) List {
        return List{ .desc = desc, .data = .empty };
    }

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn append(self: *List, allocator: std.mem.Allocator, comptime T: type, component: T) !void {
        const data: [*]const u8 = @ptrCast(@alignCast(&component));
        try self.data.appendSlice(allocator, data[0..@sizeOf(T)]);
    }

    pub fn appendRaw(self: *List, allocator: std.mem.Allocator, component: []const u8) !void {
        try self.data.appendSlice(allocator, component);
    }

    fn swapRemoveRaw(self: *List, index: usize, dest: *[]u8) void {
        var i = self.desc.size;
        while (i > 0) {
            i -= 1;
            dest.*[i] = self.data.swapRemove(index * self.desc.size + i);
        }
    }

    fn swapDelete(self: *List, index: usize) void {
        var i = self.desc.size;
        while (i > 0) {
            i -= 1;
            _ = self.data.swapRemove(index * self.desc.size + i);
        }
    }

    pub fn get(self: *List, comptime T: type) []const T {
        const count = self.data.items.len / self.desc.size;
        return @as([*]const T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getMut(self: *List, comptime T: type) []T {
        const count = self.data.items.len / self.desc.size;
        return @as([*]T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getSingleRaw(self: *List, index: usize) []const u8 {
        return @as([*]u8, @ptrCast(@alignCast(self.data.items.ptr)))[index .. index + self.desc.size];
    }
};

pub const Description = struct {
    size: usize,
    alignment: usize,
    name: [:0]const u8,

    pub fn get(T: type) Description {
        return .{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .name = @typeName(T),
        };
    }
};

test "Basic" {
    const Position = struct { x: i32, y: i32, z: i32 };
    const allocator = std.testing.allocator;

    var list = List.init(Description.get(Position));
    defer list.deinit(allocator);

    const a = Position{ .x = 12, .y = -42, .z = 1 };
    const b = Position{ .x = 13, .y = -44, .z = 1 };

    try list.append(allocator, Position, a);
    try list.append(allocator, Position, b);

    var values = list.getMut(Position);
    try std.testing.expect(values.len == 2);
    try std.testing.expectEqual(a, values[0]);
    try std.testing.expectEqual(b, values[1]);

    values[0].z = -7;

    values = list.getMut(Position);
    try std.testing.expect(values.len == 2);
    try std.testing.expectEqual(Position{ .x = 12, .y = -42, .z = -7 }, values[0]);
    try std.testing.expectEqual(b, values[1]);
}
