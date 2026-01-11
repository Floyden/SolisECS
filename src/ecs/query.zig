const std = @import("std");
const ecs = @import("solis_ecs");
const World = ecs.World;

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
        entities: ?[]ecs.Entity,
        archetype: usize,
        binding: ComponentBinding,

        pub fn create(query: *const Q) Self {
            return .{
                .query = query,
                .entities = null,
                .archetype = 0,
                .binding = undefined,
            };
        }

        fn createBinding(self: *Self) void {
            std.debug.assert(self.query.archetypes.items.len > self.archetype);
            const archetype: *ecs.Archetype = self.query.archetypes.items[self.archetype];
            self.entities = archetype.entities.items;

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
            self.entities = null;
            return null;
        }
    };
}

pub fn TraverseIter(comptime Q: type) type {
    return struct {
        const Self = @This();
        pub const ComponentArray = Q.ComponentArray;
        pub const ComponentBinding = ComponentBindings(&ComponentArray);

        query: *const Q,
        pair_iter: ecs.PairStorage.TraverseIter,
        entity: ecs.Entity,
        binding: ComponentBinding,

        pub fn init(gpa: std.mem.Allocator, query: *const Q, desc: ecs.TraverseDesc) !Self {
            return .{
                .query = query,
                .pair_iter = try query.world.pairStorage.traverse(gpa, desc),
                .entity = .none,
                .binding = undefined,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pair_iter.deinit();
        }

        fn createBinding(self: *Self, archetype: *ecs.Archetype, idx: usize) void {
            std.debug.assert(self.query.archetypes.items.len > idx);

            inline for (&self.binding) |*bind| {
                const T = @TypeOf(bind.*);
                const info = @typeInfo(T);
                if (info == .pointer) {
                    if (info.pointer.is_const) {
                        bind.* = archetype.getComponents(info.pointer.child).?[idx .. idx + 1];
                    } else {
                        bind.* = archetype.getComponentsMut(info.pointer.child).?[idx .. idx + 1];
                    }
                } else {
                    bind.* = archetype.getComponentsMut(T).?[idx .. idx + 1];
                }
            }
        }

        pub fn next(self: *Self) !?ComponentBinding {
            self.entity = try self.pair_iter.next() orelse {
                self.entity = .none;
                return null;
            };
            for (self.query.archetypes.items) |archetype| {
                if (archetype.findEntity(self.entity)) |idx| {
                    self.createBinding(archetype, idx);
                    return self.binding;
                }
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

        archetypes: std.ArrayList(*ecs.Archetype),
        world: *World,

        pub fn init(gpa: std.mem.Allocator, world: *World) !Self {
            var res: Self = .{ .archetypes = .empty, .world = world };
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

        pub fn iter(self: *Self) Iter(Self) {
            return Iter(Self).create(self);
        }

        pub fn traverse(self: *Self, gpa: std.mem.Allocator, _desc: ecs.TraverseDesc) !TraverseIter(Self) {
            var desc = _desc;
            std.debug.assert(desc.filter == null and desc.filter_ctx == null);
            const filter = struct {
                fn filter(entity: ecs.Entity, ctx: *anyopaque) bool {
                    const queue: *Self = @ptrCast(@alignCast(ctx));
                    for (queue.archetypes.items) |archetype| {
                        if (archetype.findEntity(entity)) |_| return true;
                    }
                    return false;
                }
            }.filter;

            desc.filter = filter;
            desc.filter_ctx = @ptrCast(self);

            return TraverseIter(Self).init(gpa, self, desc);
        }
    };
}
