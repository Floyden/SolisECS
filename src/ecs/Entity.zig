const Self = @This();

id: isize,

pub const none: Self = .{ .id = 0 };

// Internal Entities
pub const singletons: Self = .{ .id = -1 };
