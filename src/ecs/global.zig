const std = @import("std");
const World = @import("World.zig");
const Entity = @import("Entity.zig");

pub fn Global(T: type) type {
    return struct {
        const Self = @This();
        ptr: *T,
        pub fn init(_: std.mem.Allocator, world: *World, _: Entity) !Self {
            std.debug.assert(world.getGlobal(T) != null);
            return .{
                .ptr = world.getGlobalMut(T).?,
            };
        }
    };
}

test "Basic Globals" {
    const Foo = struct { value: u32 };

    const TestSystem = struct {
        fn system(foo: Global(Foo)) void {
            std.testing.expectEqual(1, foo.ptr.value) catch @panic("Mismatched Values");
        }
    };

    const gpa = std.testing.allocator;
    var world = try World.init(gpa);
    defer world.deinit();

    _ = try world.setGlobal(Foo, .{ .value = 1 });
    _ = try world.addSystem(gpa, TestSystem.system, .{});
    try world.step();
}
