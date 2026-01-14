const std = @import("std");
const ecs = @import("solis_ecs");

const Entity = ecs.Entity;
const System = ecs.System;
const World = ecs.World;
const Query = ecs.Query;
const QueryIter = ecs.QueryIter;

const Self = @This();
pub const Stage = struct {};

pub fn init(gpa: std.mem.Allocator, world: *World) !void {
    const schedule = try world.create(gpa);

    try world.register(gpa, Stage);

    try world.insertEntity(gpa, .stage_startup);
    try world.set(.stage_startup, Stage, .{});
    try world.insertEntity(gpa, .stage_frame_start);
    try world.set(.stage_frame_start, Stage, .{});
    try world.insertEntity(gpa, .stage_pre_update);
    try world.set(.stage_pre_update, Stage, .{});
    try world.insertEntity(gpa, .stage_update);
    try world.set(.stage_update, Stage, .{});
    try world.insertEntity(gpa, .stage_post_update);
    try world.set(.stage_post_update, Stage, .{});
    try world.insertEntity(gpa, .stage_frame_end);
    try world.set(.stage_frame_end, Stage, .{});

    try world.addPair(.stage_frame_end, Entity.DependsOn, .stage_post_update);
    try world.addPair(.stage_post_update, Entity.DependsOn, .stage_update);
    try world.addPair(.stage_update, Entity.DependsOn, .stage_pre_update);
    try world.addPair(.stage_pre_update, Entity.DependsOn, .stage_frame_start);

    world.schedule = schedule;
}

pub fn run_startup(world: *World) !void {
    // TODO: Filter disabled systems
    var query = try Query(.{*ecs.System}, .{ .deps = .{} }).init(world.allocator, world);
    defer query.deinit(world.allocator);

    var stage_iter = try world.traverse(ecs.TraverseDesc{
        .relation = ecs.typeId(Entity.DependsOn),
        .node = .stage_startup,
    });
    defer stage_iter.deinit();

    while (try stage_iter.next()) |stage| {
        var sys_iter = try query.traverse(world.allocator, .{
            .reversed = true,
            .node = stage,
            .relation = ecs.typeId(Entity.DependsOn),
        });
        defer sys_iter.deinit();

        while (try sys_iter.next()) |node| {
            const system: *ecs.System = &node.@"0"[0];
            if (system.last_frame < world.frame) {
                system.callback(system.context);
                system.last_frame = world.frame;
            }
        }
    }
}

var startup_executed = [2]bool{ false, false };
test "Startup" {
    const Systems = struct {
        fn test_system1() void {
            startup_executed[0] = true;
        }
        fn test_system2() void {
            startup_executed[1] = true;
        }
    };

    const gpa = std.testing.allocator;
    var world = try World.init(gpa);
    defer world.deinit();
    world.frame = 1;

    try world.addSystem(gpa, Systems.test_system1, .{ .stage = .stage_startup });
    try world.addSystem(gpa, Systems.test_system2, .{ .stage = .stage_startup });

    try run_startup(&world);

    try std.testing.expect(startup_executed[0]);
    try std.testing.expect(startup_executed[1]);
}
