const std = @import("std");
const Archetype = @import("Archetype.zig");
const World = @import("World.zig");
const Entity = @import("Entity.zig");

fn parseTupleTypes(comptime tuple: anytype) [@typeInfo(@TypeOf(tuple)).@"struct".fields.len]type {
    const TupleType = @TypeOf(tuple);
    const type_info = @typeInfo(TupleType);

    const fields = type_info.@"struct".fields;
    const type_array: [fields.len]type = comptime blk: {
        var res: [fields.len]type = undefined;
        for (&res, 0..) |*dst, i| {
            const field_name = std.fmt.comptimePrint("{}", .{i});
            dst.* = @field(tuple, field_name);
        }
        break :blk res;
    };
    return type_array;
}

pub fn Iter(Q: anytype) type {
    return struct {
        const Self = @This();
        pub const ComponentArray = Q.ComponentArray;

        query: *const Q,
        entity: Entity,
        archetype: usize,
        component: usize,

        pub fn create(query: *const Q) Self {
            return .{
                .query = query,
                .entity = .none,
                .archetype = 0,
                .component = 0,
            };
        }

        pub fn next(self: *Self) ?void {
            const archetypes = self.query.archetypes.items;
            while (archetypes.len > self.archetype) {
                if (archetypes[self.archetype].count() > self.component) {
                    defer self.component += 1;
                    self.entity = archetypes[self.archetype].entities.items[self.component];
                    return;
                }
                self.archetype += 1;
                self.component = 0;
            }
            self.entity = .none;
            return null;
        }
    };
}

pub fn Query(components: anytype, filters: anytype) type {
    return struct {
        const Self = @This();
        pub const ComponentArray = parseTupleTypes(components);
        pub const FilterArray = parseTupleTypes(filters);

        // world: *World,
        archetypes: std.ArrayList(*Archetype),
        // pointers: std.ArrayList([ComponentArray.len]*anyopaque),

        pub fn init(gpa: std.mem.Allocator, world: *World) !Self {
            var res: Self = .{ .archetypes = .empty };
            outer: for (world.storage.archetypes.items) |archetype| {
                if (archetype.components.items.len < ComponentArray.len) continue;
                std.log.debug("{}", .{archetype.components});

                // skip archetypes which do not contain the component
                inline for (ComponentArray) |component| {
                    const info = @typeInfo(component);
                    if (info == .pointer and !archetype.hasType(info.pointer.child)) {
                        continue :outer;
                    } else if (info == .@"struct" and !archetype.hasType(component)) {
                        continue :outer;
                    }
                }

                try res.archetypes.append(gpa, archetype);
                // try res.pointers.append(gpa, undefined);
                // var back = res.pointers.getLast();
                // inline for (ComponentArray, 0..) |component, i| {
                //     back[i] = @ptrCast(archetype.getComponents(component).?);
                // }
            }
            return res;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.archetypes.deinit(gpa);
        }
    };
}
