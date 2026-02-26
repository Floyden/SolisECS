const Self = @This();

id: isize,

pub const none: Self = .{ .id = 0 };

// Internal Entities
pub const globals: Self = .{ .id = -1 };

// Comparison Entities
pub const any: Self = .{ .id = -2 };

// System Stages
pub const stage_startup: Self = .{ .id = -100 };
pub const stage_frame_start: Self = .{ .id = -101 };
pub const stage_pre_update: Self = .{ .id = -102 };
pub const stage_update: Self = .{ .id = -103 };
pub const stage_post_update: Self = .{ .id = -104 };
pub const stage_frame_end: Self = .{ .id = -105 };

// Pairs
pub const DependsOn = struct {};
