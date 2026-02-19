const std = @import("std");
const ecs = @import("solis_ecs");

const Self = @This();

const ApplyFunc: type = *const fn (?*anyopaque, *ecs.World) void;
const Command = struct {
    apply: ApplyFunc,
    ctx: ?*anyopaque,
    d_tor: ?*const fn (*anyopaque, std.mem.Allocator) void = null,
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

pub fn spawn(self: *Self, gpa: std.mem.Allocator, components: anytype) !void {
    const cmd = try SpawnCommand(@TypeOf(components)).createCommand(gpa, components);
    try self.buffer.append(gpa, cmd);
}

pub fn spawnEmpty(self: *Self, gpa: std.mem.Allocator) !void {
    try self.queue(gpa, SpawnCommand(.{}).spawnTask, null);
}

fn SpawnCommand(ComponentT: type) type {
    return struct {
        const SpawnCommandT = @This();

        components: ComponentT,
        fn spawnTask(self_opt: ?*anyopaque, world: *ecs.World) void {
            const entity = world.create(world.allocator) catch @panic("Entity Creation failed");
            std.log.debug("Spawned Entity", .{});
            if (@as(?*SpawnCommandT, @ptrCast(self_opt))) |self| {
                inline for (self.components) |component| {
                    world.set(entity, @TypeOf(component), component) catch @panic("Failed to set components");
                }
                std.log.debug("With components: {}", .{self.components});
            }
        }

        fn createCommand(gpa: std.mem.Allocator, components: ComponentT) !Command {
            return Command{
                .apply = spawnTask,
                .ctx = try allocate(gpa, components),
                .d_tor = deallocate,
            };
        }

        fn allocate(gpa: std.mem.Allocator, components: ComponentT) !*SpawnCommandT {
            const res = try gpa.create(SpawnCommandT);
            res.components = components;
            return res;
        }

        fn deallocate(self: *anyopaque, gpa: std.mem.Allocator) void {
            gpa.destroy(@as(*SpawnCommandT, @ptrCast(self)));
        }
    };
}

test "Basic" {}
