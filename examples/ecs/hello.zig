const std = @import("std");
const ecs = @import("ecs");

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

pub fn Move(iter: *ecs.Iter) void {
    var position = iter.getFieldMut(Position, 0);
    const velocity = iter.getField(Velocity, 1);

    for (0..iter.count) |i| {
        position[i].x += velocity[i].y;
    }
}

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var world = ecs.World.init(allocator.allocator());
    defer world.deinit();

    try world.register(.{ Position, Velocity });
    try world.addSystem(Move, .{ Position, Velocity });

    const foo = try world.create();
    try world.set(foo, Position, .{ .x = 0, .y = 0 });
    try world.set(foo, Velocity, .{ .x = 1, .y = 0 });

    world.step();

    const pos = world.get(foo, Position);
    std.log.info("New Position: {?}", .{pos});
}
