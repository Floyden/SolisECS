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
    _ = world;
    // const query = Query(.{System}, .{.deps = .{}});

    // 0. Find all systems
    // 1. Find all stages which depend on .stage_startup
    // 2. Traverse throguh all found stages, executing all systems within a stage.
    // 3. Respect the dependencies of every system.
}
