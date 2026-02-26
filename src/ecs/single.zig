const std = @import("std");
const World = @import("World.zig");
const Entity = @import("Entity.zig");

pub fn Single(T: type) type {
    return struct {
        const Self = @This();
        value: *T,
        pub fn init(_: std.mem.Allocator, world: *World, _: Entity) !Self {
            std.debug.assert(world.getSingleton(T) != null);
            return .{
                .value = world.getSingletonMut(T).?,
            };
        }

        pub fn get(self: Self) *const T {
            return self.value;
        }

        pub fn getMut(self: Self) *T {
            return self.value;
        }
    };
}

test "Basic Singles" {
    const Foo = struct { value: u32 };

    const TestSystem = struct {
        fn system(foo: Single(Foo)) void {
            std.testing.expectEqual(1, foo.get().value) catch @panic("Mismatched Values");
        }
    };

    const gpa = std.testing.allocator;
    var world = try World.init(gpa);
    defer world.deinit();

    _ = try world.setSingleton(Foo, .{ .value = 1 });
    try world.addSystem(gpa, TestSystem.system, .{});
    try world.step();
}
