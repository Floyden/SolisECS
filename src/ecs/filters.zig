const ecs = @import("solis_ecs");

pub fn Changed(comptime T: type) type {
    return struct {
        const Type = T;

        last_frame: ecs.World.Frame = .{},
        current_frame: ecs.World.Frame = .{},

        pub fn match(self: @This(), archetype: *const ecs.Archetype) bool {
            const modified = archetype.getLastModified(T) orelse return false;
            if (modified.greaterThan(self.last_frame)) return true;
            return false;
        }

        pub fn prepare(self: *@This(), world: *ecs.World) void {
            self.last_frame = self.current_frame;
            self.current_frame = world.frame;
        }
    };
}
