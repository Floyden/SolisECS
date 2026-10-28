const std = @import("std");
const ecs = @import("solis_ecs");
const World = ecs.World;

fn parseTupleTypes(comptime tuple: anytype) [@typeInfo(@TypeOf(tuple)).@"struct".field_types.len]type {
    const TupleType = @TypeOf(tuple);
    const type_info = @typeInfo(TupleType);

    // const field_types = type_info.@"struct".field_types;
    // const type_array: [field_types.len]type = comptime blk: {
    //     var res: [field_types.len]type = undefined;
    //     for (&res, field_types) |*dst, i| {
    //         dst.* = i;

    const fields = type_info.@"struct".field_names;
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
            if (info.pointer.attrs.@"const") {
                R.* = []const info.pointer.child;
            } else {
                R.* = []info.pointer.child;
            }
        } else {
            R.* = []const T;
        }
    }
    return @Tuple(&res);
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
                    if (info.pointer.attrs.@"const") {
                        bind.* = archetype.getComponents(info.pointer.child).?;
                    } else {
                        archetype.markComponentModified(info.pointer.child, self.query.world.frame);
                        bind.* = archetype.getComponentsMut(info.pointer.child).?;
                    }
                } else {
                    bind.* = archetype.getComponents(T).?;
                }
            }
            self.binding = binding;
        }

        pub fn next(self: *Self) ?ComponentBinding {
            const archetypes = self.query.archetypes.items;
            outer: while (archetypes.len > self.archetype) {
                defer self.archetype += 1;
                const archetype: *ecs.Archetype = self.query.archetypes.items[self.archetype];
                if (archetype.entities.items.len == 0)
                    continue;
                inline for (self.query.filter_instances) |filter| if (!filter.match(archetype)) continue :outer;

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

        fn createBinding(self: *Self, archetype: *ecs.Archetype, idx: usize) void {
            std.debug.assert(archetype.entities.items.len > idx);

            var binding: ComponentBinding = undefined;
            inline for (&binding) |*bind| {
                const T = @TypeOf(bind.*);
                const info = @typeInfo(T);
                if (info == .pointer) {
                    if (info.pointer.attrs.@"const") {
                        bind.* = archetype.getComponents(info.pointer.child).?[idx .. idx + 1];
                    } else {
                        archetype.markComponentModified(info.pointer.child, self.query.world.frame);
                        bind.* = archetype.getComponentsMut(info.pointer.child).?[idx .. idx + 1];
                    }
                } else {
                    bind.* = archetype.getComponents(T).?[idx .. idx + 1];
                }
            }
            self.binding = binding;
        }

        pub fn next(self: *Self) !?ComponentBinding {
            while (try self.pair_iter.next()) |entity| {
                outer: for (self.query.archetypes.items) |archetype| {
                    inline for (self.query.filter_instances) |filter| if (!filter.match(archetype)) continue :outer;
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
        pub const ComponentArray = parseTupleTypes(Components);
        pub const FilterArray = parseTupleTypes(filters);
        pub const FilterTuple = @Tuple(&FilterArray);

        archetypes: std.ArrayList(*ecs.Archetype),
        filter_instances: FilterTuple,
        world: *World,

        pub fn init(_: std.mem.Allocator, world: *World, _: ecs.Entity) !Self {
            const filter_info = @typeInfo(FilterTuple).@"struct";
            var filter_instances: FilterTuple = undefined;
            inline for (filter_info.field_types, filter_info.field_names) |T, name| {
                @field(filter_instances, name) = @as(T, .{});
            }

            var res: Self = .{
                .archetypes = .empty,
                .world = world,
                .filter_instances = filter_instances,
            };
            res.collectArchetypes(world);
            return res;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.archetypes.deinit(gpa);
        }

        pub fn prepare(self: *Self, world: *World) void {
            self.collectArchetypes(world);
            inline for (&self.filter_instances) |*filter| filter.prepare(world);
        }

        fn collectArchetypes(self: *Self, world: *World) void {
            self.archetypes.clearRetainingCapacity();
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

test "track mutable access" {
    const Position = struct { x: f32, y: f32 };
    const gpa = std.testing.allocator;
    var world = try ecs.World.init(gpa, std.testing.io);
    defer world.deinit();

    _ = try world.create(gpa, Position{ .x = 1, .y = 2 });

    // A read-only binding must not mark the component.
    var read_query = try Query(.{Position}, .{}).init(gpa, &world, .none);
    defer read_query.deinit(gpa);
    var read_iter = read_query.iter();
    _ = read_iter.next() orelse return error.TestExpectedEqual;
    const initial = read_query.archetypes.items[0].getLastModified(Position).?;
    try std.testing.expectEqual(@as(u64, 0), initial.tick);
    try std.testing.expectEqual(@as(u64, 1), initial.subtick.load(.monotonic));

    // Mutable query bindings must mark the actual component type.
    _ = world.frame.advanceSubtick();
    var mut_query = try Query(.{*Position}, .{}).init(gpa, &world, .none);
    defer mut_query.deinit(gpa);
    var mut_iter = mut_query.iter();
    _ = mut_iter.next() orelse return error.TestExpectedEqual;

    const modified = mut_query.archetypes.items[0].getLastModified(Position).?;
    try std.testing.expectEqual(world.frame.tick, modified.tick);
    try std.testing.expectEqual(
        world.frame.subtick.load(.monotonic),
        modified.subtick.load(.monotonic),
    );
}

test "query changed components" {
    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { x: f32, y: f32 };
    const gpa = std.testing.allocator;
    var world = try ecs.World.init(gpa, std.testing.io);
    defer world.deinit();

    _ = try world.create(gpa, Position{ .x = 1, .y = 2 });
    _ = try world.create(gpa, .{ Position{ .x = 2, .y = 3 }, Velocity{ .x = 1, .y = 2 } });

    var changed_query = try Query(.{Position}, .{ecs.Changed(Position)}).init(gpa, &world, .none);
    defer changed_query.deinit(gpa);
    changed_query.prepare(&world);
    var changed_iter = changed_query.iter();
    var binding = changed_iter.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Position{ .x = 1, .y = 2 }, @field(binding, "0")[0]);
    binding = changed_iter.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Position{ .x = 2, .y = 3 }, @field(binding, "0")[0]);
    try std.testing.expectEqual(null, changed_iter.next());

    // Mutable query bindings must mark the actual component type.
    _ = world.frame.advanceSubtick();
    var mut_query = try Query(.{ *Position, Velocity }, .{}).init(gpa, &world, .none);
    defer mut_query.deinit(gpa);
    var mut_iter = mut_query.iter();
    _ = mut_iter.next() orelse return error.TestExpectedEqual;

    _ = world.frame.advanceSubtick();
    changed_query.prepare(&world);
    changed_iter = changed_query.iter();
    binding = changed_iter.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(Position{ .x = 2, .y = 3 }, @field(binding, "0")[0]);
    try std.testing.expectEqual(null, changed_iter.next());
}

// test "query frame 0 changes" {
//     const Position = struct { x: f32, y: f32 };
//     const Velocity = struct { x: f32, y: f32 };
//     const gpa = std.testing.allocator;
//     var world = try ecs.World.init(gpa, std.testing.io);
//     defer world.deinit();
//
//     _ = try world.create(gpa, Position{ .x = 1, .y = 2 });
//     _ = try world.create(gpa, .{ Position{ .x = 2, .y = 3 }, Velocity{ .x = 1, .y = 2 } });
//
//     _ = world.frame.advanceSubtick();
//     var changed_query = try Query(.{Position}, .{ecs.Changed(Position)}).init(gpa, &world, .none);
//     defer changed_query.deinit(gpa);
//     var changed_iter = changed_query.iter();
//     const binding = changed_iter.next() orelse return error.TestExpectedEqual;
//     try std.testing.expectEqual(Position{ .x = 2, .y = 3 }, @field(binding, "0")[0]);
//     try std.testing.expectEqual(null, changed_iter.next());
// }
