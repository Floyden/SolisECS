const std = @import("std");
const solis = @import("solis_ecs");

pub fn main() !void {
    std.log.debug("Hi", .{});
    var world = solis.World.init(std.heap.page_allocator);
    defer world.deinit();
}
