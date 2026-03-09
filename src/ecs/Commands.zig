const std = @import("std");
const ecs = @import("solis_ecs");

const Self = @This();

const ApplyFunc: type = *const fn (*const Command, *ecs.World) void;
const Command = struct {
    apply: ApplyFunc,
    ctx: ?*anyopaque = null,
    entity: ecs.Entity = .none,
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
    try self.queue(gpa, Command{ .apply = SpawnCommand(.{}).spawnTask });
}

pub fn despawn(self: *Self, gpa: std.mem.Allocator, entity: ecs.Entity) !void {
    try self.queue(gpa, Command{ .apply = despawnTask, .entity = entity });
}

fn despawnTask(cmd: *const Command, world: *ecs.World) void {
    world.storage.markEntity(world.allocator, cmd.entity) catch @panic("Failed to mark entities for deletion");
}

fn SpawnCommand(ComponentT: type) type {
    return struct {
        const SpawnCommandT = @This();

        components: ComponentT,
        fn spawnTask(cmd: *const Command, world: *ecs.World) void {
            if (@as(?*SpawnCommandT, @ptrCast(@alignCast(cmd.ctx)))) |self| {
                _ = world.create(world.allocator, self.components) catch @panic("Entity Creation failed");
                world.allocator.destroy(self);
                return;
            }
            _ = world.createEmpty(world.allocator) catch @panic("Entity Creation failed");
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

test "Basic" {}
