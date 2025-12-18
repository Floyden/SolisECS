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

pub fn ComponentBindings(comptime types: []const type) type {
    var res: [types.len]type = undefined;
    for (types, &res) |T, *R| {
        const info = @typeInfo(T);
        if (info == .pointer) {
            if (info.pointer.is_const) {
                R.* = []const info.pointer.child;
            } else {
                R.* = []info.pointer.child;
            }
        } else {
            R.* = []const T;
        }
    }
    return std.meta.Tuple(&res);
}
pub fn Iter(comptime Q: anytype) type {
    return struct {
        const Self = @This();
        pub const ComponentArray = Q.ComponentArray;
        pub const ComponentBinding = ComponentBindings(&ComponentArray);

        query: *const Q,
        entity: Entity,
        archetype: usize,
        binding: ComponentBinding,

        pub fn create(query: *const Q) Self {
            return .{
                .query = query,
                .entity = .none,
                .archetype = 0,
                .binding = undefined,
            };
        }

        fn createBinding(self: *Self) void {
            std.debug.assert(self.query.archetypes.items.len > self.archetype);
            const archetype = self.query.archetypes.items[self.archetype];

            inline for (&self.binding) |*bind| {
                const T = @TypeOf(bind.*);
                const info = @typeInfo(T);
                if (info == .pointer) {
                    if (info.pointer.is_const) {
                        bind.* = archetype.getComponents(info.pointer.child).?;
                    } else {
                        bind.* = archetype.getComponentsMut(info.pointer.child).?;
                    }
                } else {
                    bind.* = archetype.getComponentsMut(T).?;
                }
            }
        }

        pub fn next(self: *Self) ?ComponentBinding {
            const archetypes = self.query.archetypes.items;
            while (archetypes.len > self.archetype) {
                self.createBinding();
                defer self.archetype += 1;
                return self.binding;
            }
            self.entity = .none;
            return null;
        }
    };
}

pub fn Query(components: anytype, filters: anytype) type {
    return struct {
        const Self = @This();
        pub const Components = components;
        pub const ComponentArray = parseTupleTypes(components);
        pub const FilterArray = parseTupleTypes(filters);

        archetypes: std.ArrayList(*Archetype),

        pub fn init(gpa: std.mem.Allocator, world: *World) !Self {
            var res: Self = .{ .archetypes = .empty };
            outer: for (world.storage.archetypes.items) |archetype| {
                if (archetype.components.items.len < ComponentArray.len) continue;

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
            }
            return res;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.archetypes.deinit(gpa);
        }
    };
}
