const std = @import("std");
const iter = @import("iter.zig");
pub const Iter = iter.Iter;
pub const Query = iter.Query;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const SystemDesc = struct {
    callback: *const fn (*Iter) void,
    params: ArrayList([:0]const u8),
};
