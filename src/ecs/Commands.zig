const std = @import("std");
const ecs = @import("solis_ecs");

const Self = @This();

const ApplyFunc: type = *const fn (*const Command, *ecs.World) void;
const Command = struct {
    apply: ApplyFunc,
    ctx: ?*anyopaque = null,
    entity: ecs.Entity = .none,
};

const PointerOnlyParameter: bool = true;

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
        cmd.apply(&cmd, world);
    }
    self.buffer.clearRetainingCapacity();
}

pub fn queue(self: *Self, gpa: std.mem.Allocator, cmd: Command) !void {
    try self.buffer.append(gpa, cmd);
}

pub fn spawn(self: *Self, gpa: std.mem.Allocator, components: anytype) !void {
    const cmd = try SpawnCommand(@TypeOf(components)).createCommand(gpa, components);
    try self.queue(gpa, cmd);
}

pub fn spawnEmpty(self: *Self, gpa: std.mem.Allocator) !void {
    try self.queue(gpa, Command{ .apply = spawnEmptyTask });
}

fn spawnEmptyTask(_: *const Command, world: *ecs.World) void {
    _ = world.createEmpty(world.allocator) catch @panic("Entity Creation failed");
}

pub fn despawn(self: *Self, gpa: std.mem.Allocator, entity: ecs.Entity) !void {
    try self.queue(gpa, Command{ .apply = despawnTask, .entity = entity });
}

fn despawnTask(cmd: *const Command, world: *ecs.World) void {
    world.storage.markEntity(world.allocator, cmd.entity) catch @panic("Failed to mark entities for deletion");
}

pub fn add(self: *Self, gpa: std.mem.Allocator, entity: ecs.Entity, components: anytype) !void {
    const cmd = try AddCommand(@TypeOf(components)).createCommand(gpa, entity, components);
    try self.queue(gpa, cmd);
}

pub fn remove(self: *Self, gpa: std.mem.Allocator, entity: ecs.Entity, comptime ComponentT: type) !void {
    try self.queue(gpa, Command{ .apply = RemoveCommand(ComponentT).removeTask, .entity = entity });
}

fn RemoveCommand(ComponentT: type) type {
    return struct {
        fn removeTask(cmd: *const Command, world: *ecs.World) void {
            world.removeComponent(cmd.entity, ComponentT) catch @panic("Failed to remove component");
        }
    };
}

fn AddCommand(ComponentT: type) type {
    return struct {
        const AddCommandT = @This();

        components: ComponentT,
        fn addTask(cmd: *const Command, world: *ecs.World) void {
            const self: *AddCommandT = @ptrCast(@alignCast(cmd.ctx.?));
            world.add(world.allocator, cmd.entity, self.components) catch @panic("Adding components failed");
            world.allocator.destroy(self);
        }

        fn createCommand(gpa: std.mem.Allocator, entity: ecs.Entity, components: ComponentT) !Command {
            const res = try gpa.create(AddCommandT);
            res.components = components;
            return Command{
                .apply = addTask,
                .ctx = res,
                .entity = entity,
            };
        }
    };
}

fn SpawnCommand(ComponentT: type) type {
    return struct {
        const SpawnCommandT = @This();

        components: ComponentT,
        fn spawnTask(cmd: *const Command, world: *ecs.World) void {
            const self: *SpawnCommandT = @ptrCast(@alignCast(cmd.ctx.?));
            _ = world.create(world.allocator, self.components) catch @panic("Entity Creation failed");
            world.allocator.destroy(self);
        }

        fn createCommand(gpa: std.mem.Allocator, components: ComponentT) !Command {
            const res = try gpa.create(SpawnCommandT);
            res.components = components;
            return Command{
                .apply = spawnTask,
                .ctx = res,
            };
        }
    };
}

test "Commands emit events" {
    const gpa = std.testing.allocator;
    const Foo = struct { x: u32 };
    const Bar = struct { y: u32 };
    var world = try ecs.World.init(gpa, std.testing.io);
    defer world.deinit();

    var added = try ecs.event.Reader(ecs.event.EntityAdded).init(gpa, &world, try world.createEmpty(gpa));
    var removed = try ecs.event.Reader(ecs.event.EntityRemoved).init(gpa, &world, try world.createEmpty(gpa));
    var comp_added = try ecs.event.Reader(ecs.event.ComponentAdded).init(gpa, &world, try world.createEmpty(gpa));
    var comp_removed = try ecs.event.Reader(ecs.event.ComponentRemoved).init(gpa, &world, try world.createEmpty(gpa));
    // readers keep pointers into component storage, which moves when entities are added
    added.prepare(&world);
    removed.prepare(&world);
    comp_added.prepare(&world);
    comp_removed.prepare(&world);

    // skip events emitted during setup
    while (added.next()) |_| {}
    while (removed.next()) |_| {}
    while (comp_added.next()) |_| {}
    while (comp_removed.next()) |_| {}

    try world.commands.spawn(gpa, .{Foo{ .x = 1 }});
    try world.commands.spawnEmpty(gpa);
    world.commands.execute(&world);

    const spawned = added.next().?.entity;
    const empty = added.next().?.entity;
    try std.testing.expectEqual(@as(?ecs.event.EntityAdded, null), added.next());
    try std.testing.expectEqual(spawned.id + 1, empty.id);
    try std.testing.expectEqual(@as(u32, 1), world.get(spawned, Foo).?.x);
    try std.testing.expectEqual(ecs.typeId(Foo), comp_added.next().?.component_type);

    try world.commands.add(gpa, empty, .{ Foo{ .x = 2 }, Bar{ .y = 3 } });
    world.commands.execute(&world);
    try std.testing.expectEqual(@as(u32, 2), world.get(empty, Foo).?.x);
    try std.testing.expectEqual(@as(u32, 3), world.get(empty, Bar).?.y);
    try std.testing.expectEqual(empty.id, comp_added.next().?.entity.id);
    try std.testing.expectEqual(empty.id, comp_added.next().?.entity.id);
    try std.testing.expectEqual(@as(?ecs.event.ComponentAdded, null), comp_added.next());

    try world.commands.remove(gpa, empty, Foo);
    world.commands.execute(&world);
    try std.testing.expect(!world.has(empty, Foo));
    try std.testing.expect(world.has(empty, Bar));
    const comp_event = comp_removed.next().?;
    try std.testing.expectEqual(empty.id, comp_event.entity.id);
    try std.testing.expectEqual(ecs.typeId(Foo), comp_event.component_type);

    try world.commands.despawn(gpa, spawned);
    world.commands.execute(&world);
    try std.testing.expectEqual(@as(?ecs.event.EntityRemoved, null), removed.next());
    try world.step();
    try std.testing.expect(!world.has(spawned, Foo));
    try std.testing.expectEqual(spawned.id, removed.next().?.entity.id);
    try std.testing.expect(world.has(empty, Bar));
}
