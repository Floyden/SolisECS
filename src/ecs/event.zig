const std = @import("std");
const Entity = @import("Entity.zig");
const Global = @import("global.zig").Global;
const World = @import("World.zig");

pub fn Events(comptime Event: type) type {
    return struct {
        const Self = @This();

        next_id: usize,
        current: std.ArrayList(Event),
        old: std.ArrayList(Event),

        pub fn init() Self {
            return .{
                .next_id = 0,
                .current = .empty,
                .old = .empty,
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.current.deinit(allocator);
            self.old.deinit(allocator);
        }

        // TODO: Replace with a writer
        pub fn emit(self: *Self, allocator: std.mem.Allocator, event: Event) !void {
            self.next_id += 1;
            try self.current.append(allocator, event);
        }

        pub fn update(events: Global(Self)) void {
            events.ptr.old.clearRetainingCapacity();
            std.mem.swap(std.ArrayList(Event), &events.ptr.old, &events.ptr.current);
        }
    };
}

pub fn Cursor(comptime T: type) type {
    return struct {
        const Type = T;
        index: usize = 0,
    };
}

pub fn Reader(comptime T: type) type {
    return struct {
        pub const WorldParameter = Reader;
        pub const EventType = T;
        const Self = @This();
        events: *const Events(EventType),
        cursor_ent: Entity,
        cursor: *Cursor(T),

        pub fn init(_: std.mem.Allocator, world: *World, entity: Entity) !Self {
            std.debug.assert(entity.id > 0);
            const events = world.getGlobal(Events(EventType)) orelse {
                @panic(std.fmt.comptimePrint("Event ({}) not initialized ", .{EventType}));
            };

            const cursor = try world.set(entity, Cursor(T), .{ .index = 0 });
            return Self{
                .events = events,
                .cursor_ent = entity,
                .cursor = cursor,
            };
        }

        pub fn prepare(self: *Self, world: *World) void {
            self.cursor = world.getMut(self.cursor_ent, Cursor(T)).?;
        }

        pub fn next(self: Self) ?EventType {
            const latest = self.events.next_id;
            if (self.cursor.index >= latest) return null; // no new events
            if (self.events.current.items.len == 0 and self.events.old.items.len == 0) return null; // no events at all

            const current_base = latest - self.events.current.items.len;
            const old_base = current_base - self.events.old.items.len;
            defer self.cursor.index += 1;
            if (current_base <= self.cursor.index) // next event is a current event
                return self.events.current.items[self.cursor.index - current_base];

            if (old_base <= self.cursor.index) // next event is an old event
                return self.events.old.items[self.cursor.index - old_base];

            // has not been called for a while, refresh indices
            self.cursor.index = old_base;
            if (self.events.old.items.len > 0)
                return self.events.old.items[0];
            return self.events.current.items[0];
        }

        pub fn reset(self: *Self) void {
            self.cursor.index = self.events.next_id - self.events.current.items.len - self.events.old.items.len;
        }
    };
}

pub fn Writer(comptime T: type) type {
    return struct {
        pub const WorldParameter = Writer;
        pub const EventType = T;
        const Self = @This();
        events: *Events(EventType),

        pub fn init(world: *World, _: u64) !Self {
            const events_opt = world.getGlobalMut(Events(EventType));

            if (events_opt) |events|
                return Self.create(events);
            return error.EventNotInitialized;
        }

        pub fn create(events: *Events(EventType)) Self {
            return Self{ .events = events };
        }

        pub fn emit(self: Self, allocator: std.mem.Allocator, event: EventType) !void {
            try self.events.emit(allocator, event);
        }
    };
}

pub fn register(world: *World, T: type) !void {
    try world.register(world.allocator, Events(T));
    try world.register(world.allocator, Reader(T));
    try world.register(world.allocator, Writer(T));
    try world.register(world.allocator, Cursor(T));
    _ = try world.setGlobal(Events(T), Events(T).init());
    _ = try world.addSystem(world.allocator, Events(T).update, .{ .stage = .stage_frame_start });
}

test "Basic Events" {
    const gpa = std.testing.allocator;
    const TestEvent = struct { id: usize };
    var world = try World.init(gpa, std.testing.io);
    defer world.deinit();

    try register(&world, TestEvent);

    const reader_ent = try world.create(gpa, .{});
    var reader = try Reader(TestEvent).init(gpa, &world, reader_ent);
    var writer = try Writer(TestEvent).init(&world, 0);

    try writer.emit(gpa, .{ .id = 1 });
    try writer.emit(gpa, .{ .id = 2 });
    try world.step();
    try writer.emit(gpa, .{ .id = 3 });

    try std.testing.expectEqual(@as(?usize, 1), reader.next().?.id);
    try std.testing.expectEqual(@as(?usize, 2), reader.next().?.id);
    try std.testing.expectEqual(@as(?usize, 3), reader.next().?.id);
    try std.testing.expectEqual(@as(?TestEvent, null), reader.next());

    try world.step();
    reader.prepare(&world);
    reader.reset();
    try writer.emit(gpa, .{ .id = 4 });

    try std.testing.expectEqual(@as(?usize, 3), reader.next().?.id);
    try std.testing.expectEqual(@as(?usize, 4), reader.next().?.id);
    try std.testing.expectEqual(@as(?TestEvent, null), reader.next());
}
