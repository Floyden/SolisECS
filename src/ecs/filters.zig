const ecs = @import("solis_ecs");

pub fn Changed(comptime T: type) type {
    return struct {
        const Type = T;

        last_frame: ecs.World.Frame = .{},
        current_frame: ecs.World.Frame = .{},

        pub fn match(self: @This(), archetype: *const ecs.Archetype) bool {
            if (!archetype.hasType(T)) return false;
            const modified = archetype.getLastModified(T) orelse return true;
            if (modified.greaterThan(self.last_frame)) return true;
            return false;
        }

        pub fn prepare(self: *@This(), world: *ecs.World) void {
            self.last_frame = self.current_frame;
            self.current_frame = world.frame;
        }
    };
}

/// Returns true if any of T1 or T2 match
pub fn Or(comptime T1: type, comptime T2: type) type {
    return struct {
        t1: T1 = .{},
        t2: T2 = .{},

        pub fn match(self: @This(), archetype: *const ecs.Archetype) bool {
            return self.t1.match(archetype) or self.t2.match(archetype);
        }

        pub fn prepare(self: *@This(), world: *ecs.World) void {
            self.t1.prepare(world);
            self.t2.prepare(world);
        }
    };
}
