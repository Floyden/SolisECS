const ecs = @import("solis_ecs");
const std = @import("std");

pub const SystemDesc = struct {
    stage: ecs.Entity = .stage_update,
    // dependencies
};

pub const System = struct {
    callback: *const fn (*anyopaque) void,
    deinit_cb: *const fn (*anyopaque, gpa: std.mem.Allocator) void,
    context: *anyopaque,
    last_frame: u64 = 0,

    pub fn deinit(self: *System, gpa: std.mem.Allocator) void {
        @call(.auto, self.deinit_cb, .{ self.context, gpa });
    }

    pub fn invoke(self: System) void {
        @call(.auto, self.callback, .{self.context});
    }
};
