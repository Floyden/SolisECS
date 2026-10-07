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
        binding: ?ComponentBinding,

        pub fn create(query: *const Q) Self {
            return .{
                .query = query,
                .entities = null,
                .archetype = 0,
                .binding = null,
            };
        }

        fn createBinding(self: *Self) void {
            std.debug.assert(self.query.archetypes.items.len > self.archetype);
            const archetype: *ecs.Archetype = self.query.archetypes.items[self.archetype];
            self.entities = archetype.entities.items;

            var binding: ComponentBinding = undefined;
            inline for (&binding) |*bind| {
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
            self.binding = binding;
        }

        pub fn next(self: *Self) ?ComponentBinding {
            const archetypes = self.query.archetypes.items;
            while (archetypes.len > self.archetype) {
                defer self.archetype += 1;
                const archetype: *ecs.Archetype = self.query.archetypes.items[self.archetype];
                if (archetype.entities.items.len == 0)
                    continue;

                self.createBinding();
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
        binding: ?ComponentBinding,

        pub fn init(gpa: std.mem.Allocator, query: *const Q, desc: ecs.TraverseDesc) !Self {
            return .{
                .query = query,
                .pair_iter = try query.world.pairStorage.traverse(gpa, desc),
                .entity = .none,
                .binding = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pair_iter.deinit();
        }

        fn createBinding(self: *Self, archetype: *const ecs.Archetype, idx: usize) void {
            std.debug.assert(archetype.entities.items.len > idx);

            var binding: ComponentBinding = undefined;
            inline for (&binding) |*bind| {
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
            self.binding = binding;
        }

        pub fn next(self: *Self) !?ComponentBinding {
            while (try self.pair_iter.next()) |entity| {
                for (self.query.archetypes.items) |archetype| {
                    if (archetype.findEntity(entity)) |idx| {
                        self.entity = entity;
                        self.createBinding(archetype, idx);
                        return self.binding;
                    }
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

        pub fn init(_: std.mem.Allocator, world: *World, _: ecs.Entity) !Self {
            var res: Self = .{ .archetypes = .empty, .world = world };
            res.prepare(world);
            return res;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.archetypes.deinit(gpa);
        }

        pub fn prepare(self: *Self, world: *World) void {
            self.archetypes.clearRetainingCapacity();
            outer: for (self.world.storage.archetypes.items) |archetype| {
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

                self.archetypes.append(world.allocator, archetype) catch @panic("OOM");
            }
        }

        pub fn iter(self: *const Self) Iter(Self) {
            return Iter(Self).create(self);
        }

        pub fn traverse(self: *const Self, gpa: std.mem.Allocator, _desc: ecs.TraverseDesc) !TraverseIter(Self) {
            var desc = _desc;
            const filter = struct {
                fn filter(entity: ecs.Entity, ctx: *const anyopaque) bool {
                    const queue: *const Self = @ptrCast(@alignCast(ctx));
                    for (queue.archetypes.items) |archetype| {
                        if (archetype.findEntity(entity)) |_| return true;
                    }
                    return false;
                }
            }.filter;

            desc.filter = .{ .func = filter, .ctx = @ptrCast(self) };

            return TraverseIter(Self).init(gpa, self, desc);
        }
    };
}
