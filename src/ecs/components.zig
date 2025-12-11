const std = @import("std");
const ArrayList = std.ArrayList;

pub const List = struct {
    desc: Description,
    data: ArrayList(usize),

    pub fn init(desc: Description) List {
        return List{ .desc = desc, .data = .empty };
    }

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }

    pub fn append(self: *List, comptime T: type, component: T) !void {
        const data: [*]const usize = @ptrCast(@alignCast(&component));
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        try self.data.appendSlice(data[0..size]);
    }

    pub fn appendRaw(self: *List, component: []const usize) !void {
        try self.data.appendSlice(component);
    }

    fn swapRemoveRaw(self: *List, index: usize, dest: *[]usize) void {
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        var i = size;
        while (i > 0) {
            i -= 1;
            dest.*[i] = self.data.swapRemove(index * size + i);
        }
    }

    fn swapDelete(self: *List, index: usize) void {
        const size = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        var i = size;
        while (i > 0) {
            i -= 1;
            _ = self.data.swapRemove(index * size + i);
        }
    }

    pub fn get(self: *List, comptime T: type) []const T {
        const offset = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        const count = self.data.items.len / offset;
        return @as([*]const T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getMut(self: *List, comptime T: type) []T {
        const offset = std.math.divCeil(usize, self.desc.size, @sizeOf(usize)) catch unreachable;
        const count = self.data.items.len / offset;
        return @as([*]T, @ptrCast(@alignCast(self.data.items.ptr)))[0..count];
    }

    pub fn getSingleRaw(self: *List, index: usize) []const usize {
        return @as([*]usize, @ptrCast(@alignCast(self.data.items.ptr)))[index .. index + 1];
    }
};

pub const Description = struct {
    size: usize,
    alignment: usize,
    name: [:0]const u8,
};
