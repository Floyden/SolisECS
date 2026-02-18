const std = @import("std");
const ecs = @import("solis_ecs");

const Self = @This();

const ApplyFunc: type = *const fn (?*anyopaque, *ecs.World) void;
const Command = struct {
    ctx: ?*anyopaque,
    apply: ApplyFunc,
};

buffer: std.ArrayList(Command),

pub fn init() Self {
    return .{
        .buffer = .empty,
    };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.buffer.deinit(gpa);
}

pub fn execute(self: *Self, world: *ecs.World) void {
    for (self.buffer.items) |cmd| {
        cmd.apply(cmd.ctx, world);
    }
    self.buffer.clearRetainingCapacity();
}

pub fn queue(self: *Self, gpa: std.mem.Allocator, func: ApplyFunc, ctx: ?*anyopaque) !void {
    try self.buffer.append(gpa, Command{ .apply = func, .ctx = ctx });
}

fn SpawnTask(components: anytype) type {
    _ = components;
    return struct {
        fn spawnTask(_: ?*anyopaque, world: *ecs.World) void {
            std.log.debug("Spawned Entity", .{});
            _ = world.create(world.allocator) catch @panic("Entity Creation failed");
        }
    };
}
//
// pub fn spawn(self: *Self, gpa: std.mem.Allocator, components: anytype) !void {
//     try self.queue(gpa, spawnTask, null);
// }

pub fn spawnEmpty(self: *Self, gpa: std.mem.Allocator) !void {
    try self.queue(gpa, SpawnTask(.{}).spawnTask, null);
}

test "Basic" {}
