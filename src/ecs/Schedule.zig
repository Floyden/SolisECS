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
    // const schedule = try world.create(gpa);

    try world.register(gpa, Stage);
    try world.register(gpa, Self);

    // try world.set(schedule, Self, .{});

    try world.insertEntity(gpa, .stage_startup);
    _ = try world.set(.stage_startup, Stage, .{});
    try world.insertEntity(gpa, .stage_frame_start);
    _ = try world.set(.stage_frame_start, Stage, .{});
    try world.insertEntity(gpa, .stage_pre_update);
    _ = try world.set(.stage_pre_update, Stage, .{});
    try world.insertEntity(gpa, .stage_update);
    _ = try world.set(.stage_update, Stage, .{});
    try world.insertEntity(gpa, .stage_post_update);
    _ = try world.set(.stage_post_update, Stage, .{});
    try world.insertEntity(gpa, .stage_frame_end);
    _ = try world.set(.stage_frame_end, Stage, .{});

    try world.addPair(.stage_frame_end, Entity.DependsOn, .stage_post_update);
    try world.addPair(.stage_post_update, Entity.DependsOn, .stage_update);
    try world.addPair(.stage_update, Entity.DependsOn, .stage_pre_update);
    try world.addPair(.stage_pre_update, Entity.DependsOn, .stage_frame_start);

    // world.schedule = schedule;
}

pub fn run_startup(world: *World) !void {
    // TODO: Filter disabled systems
    var query = try Query(.{*ecs.System}, .{}).init(world.allocator, world, .none);
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

    // TODO: Remove startup systems
}

pub fn run_pipeline(world: *World) !void {
    if (world.frame == 0)
        try run_startup(world);

    var query = try Query(.{*ecs.System}, .{}).init(world.allocator, world, .none);
    defer query.deinit(world.allocator);

    // TODO: stage_frame_start may not be the first stage of the system
    var stage_iter = try world.traverse(ecs.TraverseDesc{
        .relation = ecs.typeId(Entity.DependsOn),
        .node = .stage_frame_start,
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
                system.prepare(world);
                system.callback(system.context);
                system.last_frame = world.frame;
            }
        }
    }
    world.commands.execute(world);
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

var systems_executed = [5]bool{ false, false, false, false, false };
test "Systems" {
    const Systems = struct {
        fn test_system_start() void {
            systems_executed[0] = true;
        }
        fn test_system_pre_update() void {
            systems_executed[1] = true;
        }
        fn test_system_update() void {
            systems_executed[2] = true;
        }
        fn test_system_post_update() void {
            systems_executed[3] = true;
        }
        fn test_system_end() void {
            systems_executed[4] = true;
        }
    };

    const gpa = std.testing.allocator;
    var world = try World.init(gpa);
    defer world.deinit();
    world.frame = 1;

    try world.addSystem(gpa, Systems.test_system_start, .{ .stage = .stage_frame_start });
    try world.addSystem(gpa, Systems.test_system_pre_update, .{ .stage = .stage_pre_update });
    try world.addSystem(gpa, Systems.test_system_update, .{ .stage = .stage_update });
    try world.addSystem(gpa, Systems.test_system_post_update, .{ .stage = .stage_post_update });
    try world.addSystem(gpa, Systems.test_system_end, .{ .stage = .stage_frame_end });

    try run_pipeline(&world);

    try std.testing.expect(systems_executed[0]);
    try std.testing.expect(systems_executed[1]);
    try std.testing.expect(systems_executed[2]);
    try std.testing.expect(systems_executed[3]);
    try std.testing.expect(systems_executed[4]);
}
