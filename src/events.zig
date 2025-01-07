const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn EventWriter(comptime T: type) type {
    return struct {
        const Self = @This();
        events: *Events(T),

        pub fn new(events: *Events(T)) Self {
            return Self{ .events = events };
        }

        pub fn write(self: Self, event: T) Allocator.Error!void {
            try self.events.pushEvent(event);
        }
    };
}

pub fn EventReader(comptime T: type) type {
    return struct {
        const Self = @This();
        events: *const Events(T),
        currentEvent: usize,
        lastFrame: usize,

        pub fn new(events: *const Events(T)) Self {
            return Self{ .events = events, .currentEvent = 0, .lastFrame = 0 };
        }

        // Return the next event in the queue, returns null if there are no more events.
        pub fn next(self: *Self) ?T {
            // Might not have been called for multiple frames, catch up
            if (self.lastFrame < self.events.frame - 1) {
                self.lastFrame = self.events.frame - 1;
                self.currentEvent = 0;
            }

            // Handle missed events from last frame
            if (self.lastFrame == self.events.frame - 1) {
                if (self.currentEvent < self.events.oldBuffer().items.len) {
                    const pos = self.currentEvent;
                    self.currentEvent += 1;
                    return self.events.oldBuffer().items[pos];
                }

                self.lastFrame += 1;
                self.currentEvent = 0;
            }

            if (self.currentEvent < self.events.currentBuffer().items.len) {
                self.currentEvent += 1;
                return self.events.currentBuffer().items[self.currentEvent - 1];
            }

            return null;
        }
    };
}

// TODO: Handle multithreading
pub fn Events(comptime T: type) type {
    return struct {
        const Self = @This();
        buffers: [2]std.ArrayList(T),
        lock: std.Thread.Mutex,
        frame: usize,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .buffers = .{ std.ArrayList(T).init(allocator), std.ArrayList(T).init(allocator) },
                .lock = std.Thread.Mutex{},
                .frame = 1, // start at 1 to have an old buffer ready
            };
        }
        pub fn deinit(self: *Self) void {
            for (self.buffers) |*buffer|
                buffer.deinit();
        }

        fn pushEvent(self: *Self, event: T) !void {
            self.lock.lock();
            defer self.lock.unlock();

            try self.currentBufferMut().append(event);
        }

        fn currentBuffer(self: *const Self) *const std.ArrayList(T) {
            return &self.buffers[self.frame % 2];
        }

        fn currentBufferMut(self: *Self) *std.ArrayList(T) {
            return &self.buffers[self.frame % 2];
        }

        fn oldBuffer(self: *const Self) *const std.ArrayList(T) {
            return &self.buffers[1 - self.frame % 2];
        }

        fn oldBufferMut(self: *Self) *std.ArrayList(T) {
            return &self.buffers[1 - self.frame % 2];
        }

        pub fn update(self: *Self) void {
            self.lock.lock();
            defer self.lock.unlock();

            self.oldBufferMut().clearRetainingCapacity();
            self.frame += 1;
        }

        pub fn reader(self: *const Self) EventReader(T) {
            return EventReader(T).new(self);
        }
        pub fn writer(self: *Self) EventWriter(T) {
            return EventWriter(T).new(self);
        }
    };
}

test "Event" {
    const assert = std.debug.assert;
    const allocator = std.heap.page_allocator;
    const FooEvent = struct { foo: u32 };
    var storage = Events(FooEvent).init(allocator);
    var writer = storage.writer();
    writer.write(FooEvent{ .foo = 1 }) catch unreachable;
    storage.update();
    writer.write(FooEvent{ .foo = 2 }) catch unreachable;
    assert(storage.oldBuffer().items.len == 1);
    assert(storage.currentBuffer().items.len == 1);
    storage.update();
    assert(storage.oldBuffer().items.len == 1);
    assert(storage.currentBuffer().items.len == 0);
    writer.write(FooEvent{ .foo = 3 }) catch unreachable;
    assert(storage.currentBuffer().items.len == 1);
    var reader = storage.reader();
    assert(reader.next().?.foo == 2);
    assert(reader.next().?.foo == 3);
    assert(reader.next() == null);
}
