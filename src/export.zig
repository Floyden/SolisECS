const std = @import("std");
const ecs = @import("solis_ecs");

const c_allocator = std.heap.c_allocator;
const Entity = packed struct { e: ecs.Entity };

export fn world_init() ?*ecs.World {
    const world = c_allocator.create(ecs.World) catch return null;
    world.* = ecs.World.init(c_allocator) catch return null;
    return world;
}

export fn world_deinit(world_opt: ?*ecs.World) void {
    if (world_opt) |world| {
        world.deinit();
    }
}

export fn world_create_entity(world_opt: ?*ecs.World) @TypeOf(ecs.Entity.none.id) {
    if (world_opt) |world| {
        return (world.create(std.heap.c_allocator) catch ecs.Entity.none).id;
    }
    return ecs.Entity.none.id;
}

// export fn world_set_global(world_opt: ?*ecs.World, desc: ecs.ComponentDesc, arg: *anyopaque) ?*anyopaque {
//     if (world_opt) |world| {
//         world.setGlobal(comptime T: type, arg: T)
//     }
// }
