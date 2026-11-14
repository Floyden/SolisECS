const std = @import("std");
const ecs = @import("solis_ecs");

const Entity = ecs.Entity;
const System = ecs.System;
const World = ecs.World;
const Query = ecs.Query;
const QueryIter = ecs.QueryIter;

const Self = @This();
pub const Stage = struct {};

// First stage to run
start_stage: Entity,
system_cache: std.AutoArrayHashMapUnmanaged(Entity, []Entity) = .empty,

pub fn init(gpa: std.mem.Allocator, world: *World) !Self {
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

    return .{
        .start_stage = .stage_startup,
    };
}

const StackEntry = struct {
    entity: Entity,
    iter: ecs.PairStorage.Iterator,

    fn new(id: Entity, world: *const World, is_id_src: bool) @This() {
        return .{ .entity = id, .iter = world.pairStorage.match(.{
            .src = if (!is_id_src) id else .any,
            .dst = if (!is_id_src) .any else id,
            .relation = ecs.typeId(Entity.DependsOn),
        }) };
    }
};
fn markSystem(
    gpa: std.mem.Allocator,
    visited: *std.AutoHashMapUnmanaged(Entity, bool),
    system_ent: Entity,
) !bool {
    const entity = try visited.getOrPut(gpa, system_ent);
    if (entity.found_existing) {
        if (!entity.value_ptr.*)
            return error.CyclicDependencies;
        return false;
    }
    entity.value_ptr.* = false;
    return true;
}

pub fn createRun(gpa: std.mem.Allocator, world: *World, stage: Entity) ![]Entity {
    var systems = world.pairStorage.match(.{
        .src = .any,
        .dst = stage,
        .relation = ecs.typeId(Entity.InStage),
    });
    var visited: std.AutoHashMapUnmanaged(Entity, bool) = .empty;
    defer visited.deinit(gpa);
    var stack: std.ArrayList(StackEntry) = .empty;
    defer stack.deinit(gpa);

    var res: std.ArrayList(Entity) = .empty;

    while (systems.next()) |pair| {
        if (!try markSystem(gpa, &visited, pair.src)) continue;
        try stack.append(gpa, .new(pair.src, world, false));

        while (stack.items.len > 0) {
            var system = stack.last().?;
            if (system.iter.next()) |dep| {
                if (!world.hasPair(dep.dst, Entity.InStage, stage)) return error.DependencyOutsideStage;
                if (!try markSystem(gpa, &visited, system.entity)) continue;
                try stack.append(gpa, .new(pair.src, world, true));
            } else {
                _ = stack.pop();
                visited.getPtr(system.entity).?.* = true;
                try res.append(gpa, system.entity);
            }
        }
    }
    return try res.toOwnedSlice(gpa);
}

pub fn runPipeline(self: *Self, gpa: std.mem.Allocator, world: *World) !void {
    var query = try Query(.{*ecs.System}, .{}).init(gpa, world, .none);
    defer query.deinit(gpa);

    var stage_iter = try world.traverse(ecs.TraverseDesc{
        .relation = ecs.typeId(Entity.DependsOn),
        .reversed = true,
        .node = self.start_stage,
    });
    defer stage_iter.deinit();

    while (try stage_iter.next()) |stage| {
        var sys_iter = try query.traverse(gpa, .{
            .reversed = true,
            .node = stage,
            .relation = ecs.typeId(Entity.InStage),
        });
        defer sys_iter.deinit();

        while (try sys_iter.next()) |_| {
            try runSystem(world, sys_iter.entity);
        }
    }

    if (world.frame.tick == 1 and self.start_stage.id == Entity.stage_startup.id) {
        self.start_stage = .stage_frame_start;
        try self.runPipeline(gpa, world);
    }

    _ = world.frame.advanceSubtick();
    world.commands.execute(world);
}

pub fn runSystem(world: *World, entity: Entity) !void {
    var system = world.getMut(entity, System) orelse return;
    if (system.last_frame.tick >= world.frame.tick) return;
    if (system.state.cmpxchgStrong(.idle, .pending, .acq_rel, .acquire) != null) return;
    errdefer {
        if (world.getMut(entity, System)) |sys|
            sys.state.store(.idle, .release);
    }

    // TODO: Replace this by a cached topologically sorted run
    var deps = world.pairStorage.match(.{
        .src = entity,
        .dst = .any,
        .relation = ecs.typeId(Entity.DependsOn),
    });
    while (deps.next()) |dep| {
        try runSystem(world, dep.dst);
    }

    system = world.getMut(entity, System) orelse return; // system may have changed due to other systems
    system.last_frame = world.frame.advanceSubtick();
    system.prepare(world);
    system.state.store(.running, .release);
    system.callback(system.context);
    system.state.store(.idle, .release);
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
    var world = try World.init(gpa, std.testing.io);
    defer world.deinit();

    _ = try world.addSystem(gpa, Systems.test_system1, .{ .stage = .stage_startup });
    _ = try world.addSystem(gpa, Systems.test_system2, .{ .stage = .stage_startup });

    try world.step();

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
    var world = try World.init(gpa, std.testing.io);
    defer world.deinit();

    _ = try world.addSystem(gpa, Systems.test_system_start, .{ .stage = .stage_frame_start });
    _ = try world.addSystem(gpa, Systems.test_system_pre_update, .{ .stage = .stage_pre_update });
    _ = try world.addSystem(gpa, Systems.test_system_update, .{ .stage = .stage_update });
    _ = try world.addSystem(gpa, Systems.test_system_post_update, .{ .stage = .stage_post_update });
    _ = try world.addSystem(gpa, Systems.test_system_end, .{ .stage = .stage_frame_end });

    try world.step();

    try std.testing.expect(systems_executed[0]);
    try std.testing.expect(systems_executed[1]);
    try std.testing.expect(systems_executed[2]);
    try std.testing.expect(systems_executed[3]);
    try std.testing.expect(systems_executed[4]);
}

test "createRun" {
    const Systems = struct {
        fn system() void {}
    };

    const gpa = std.testing.allocator;
    var world = try World.init(gpa, std.testing.io);
    defer world.deinit();

    const other = try world.addSystem(gpa, Systems.system, .{ .stage = .stage_pre_update });
    const first = try world.addSystem(gpa, Systems.system, .{ .stage = .stage_update });
    const last = try world.addSystem(gpa, Systems.system, .{ .stage = .stage_update, .predecessors = &.{first} });
    const middle = try world.addSystem(gpa, Systems.system, .{
        .stage = .stage_update,
        .predecessors = &.{other},
        .successors = &.{last},
    });

    const run = try createRun(gpa, &world, .stage_update);
    defer gpa.free(run);

    const index = struct {
        fn of(items: []const Entity, e: Entity) usize {
            for (items, 0..) |item, i| if (item.id == e.id) return i;
            unreachable;
        }
    }.of;
    try std.testing.expectEqual(@as(usize, 3), run.len);
    for (run) |e| try std.testing.expect(e.id != other.id);
    try std.testing.expect(index(run, first) < index(run, last));
    try std.testing.expect(index(run, middle) < index(run, last));

    try world.addPair(first, Entity.DependsOn, last);
    try std.testing.expectError(error.DependencyCycle, createRun(gpa, &world, .stage_update));
}
