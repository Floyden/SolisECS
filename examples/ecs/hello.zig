const std = @import("std");
const ecs = @import("ecs");

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };

pub fn Move(iter: *ecs.Iter) void {
    while (iter.next()) |*tuple| {
        var position = tuple.getMut(Position, 0);
        const velocity = tuple.get(Velocity, 1);
        position.x += velocity.x;
        position.y += velocity.y;
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

    const bar = try world.create();
    try world.set(bar, Position, .{ .x = 3, .y = 2 });
    try world.set(bar, Velocity, .{ .x = 2, .y = 3 });
    world.step();

    const pos = world.get(foo, Position);
    const pos2 = world.get(bar, Position);
    std.log.info("New Position 1: {?}", .{pos});
    std.log.info("New Position 2: {?}", .{pos2});
}
