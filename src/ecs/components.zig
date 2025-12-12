const std = @import("std");
const type_id = @import("type_id.zig");
const ArrayList = std.ArrayList;

pub const List = struct {
    desc: Description,
    data: ArrayList(u8),

    pub fn init(desc: Description) List {
        return List{ .desc = desc, .data = .empty };
    }

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        if (self.desc.deinit) |deinit_ptr_raw| {
            const deinit_ptr: *const fn (*anyopaque, std.mem.Allocator) void = @ptrCast(deinit_ptr_raw);
            var i: usize = 0;
            while (i < self.data.items.len) : (i += self.desc.size) {
                deinit_ptr(&self.data.items[i], allocator);
            }
        }
        self.data.deinit(allocator);
    }

    pub fn allocate(self: *List, allocator: std.mem.Allocator, comptime T: type, n: usize) !void {
        try self.data.appendNTimes(allocator, 0, @sizeOf(T) * n);
    }

    pub fn append(self: *List, allocator: std.mem.Allocator, comptime T: type, component: T) !void {
        const data: [*]const u8 = @ptrCast(@alignCast(&component));
        try self.data.appendSlice(allocator, data[0..@sizeOf(T)]);
    }

    pub fn appendRaw(self: *List, allocator: std.mem.Allocator, component: []const u8) !void {
        try self.data.appendSlice(allocator, component);
    }

    pub fn appendEmpty(self: *List, allocator: std.mem.Allocator) !void {
        try self.data.appendNTimes(allocator, 0, self.desc.size);
    }

    pub fn swapRemoveRaw(self: *List, index: usize, dest: *[]u8) void {
        var i = self.desc.size;
        while (i > 0) {
            i -= 1;
            dest.*[i] = self.data.swapRemove(index * self.desc.size + i);
        }
    }

    pub fn swapRemove(self: *List, index: usize) void {
        var i = self.desc.size;
        while (i > 0) {
            i -= 1;
            _ = self.data.swapRemove(index * self.desc.size + i);
        }
    }

    pub fn get(self: *const List, comptime T: type) []const T {
        return @as([*]const T, @ptrCast(@alignCast(self.data.items.ptr)))[0..self.count()];
    }

    pub fn getMut(self: *const List, comptime T: type) []T {
        return @as([*]T, @ptrCast(@alignCast(self.data.items.ptr)))[0..self.count()];
    }

    pub fn getSingleRaw(self: *const List, index: usize) []const u8 {
        return @as([*]u8, @ptrCast(@alignCast(self.data.items.ptr)))[index .. index + self.desc.size];
    }

    pub fn count(self: *const List) usize {
        if (self.desc.size > 1) {
            return self.data.items.len / self.desc.size;
        } else {
            return self.data.items.len;
        }
    }
};

pub const Description = struct {
    size: usize,
    alignment: u16,
    id: type_id.TypeId,
    deinit: ?*const anyopaque,

    pub fn get(comptime T: type) Description {
        comptime var deinit_ptr: ?*const anyopaque = null;

        if (@hasDecl(T, "deinit")) {
            deinit_ptr = @ptrCast(&@field(T, "deinit"));
        }

        return .{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .id = type_id.typeId(T),
            .deinit = deinit_ptr,
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
