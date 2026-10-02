const ecs = @import("solis_ecs");
const std = @import("std");

pub const SystemDesc = struct {
    stage: ecs.Entity = .stage_update,
    // dependencies
};

pub const System = struct {
    callback: *const fn (*anyopaque) void,
    deinit_cb: *const fn (*anyopaque, std.mem.Allocator) void,
    prepare_cb: *const fn (*anyopaque, *ecs.World) void,
    context: *anyopaque,
    last_frame: usize = 0,

    pub fn deinit(self: *System, gpa: std.mem.Allocator) void {
        @call(.auto, self.deinit_cb, .{ self.context, gpa });
    }

    pub fn invoke(self: System) void {
        @call(.auto, self.callback, .{self.context});
    }

    pub fn prepare(self: System, world: *ecs.World) void {
        @call(.auto, self.prepare_cb, .{ self.context, world });
    }
};
