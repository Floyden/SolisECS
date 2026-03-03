const std = @import("std");
const ecs = @import("solis_ecs");
const ArrayList = std.ArrayList;

pub const List = struct {
    desc: Description,
    data: ArrayList(u8),

    pub fn init(desc: Description) List {
        return List{ .desc = desc, .data = .empty };
    }

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        if (self.desc.deinit) |deinit_ptr_raw| {
            const deinit_ptr: *const fn (*anyopaque, std.mem.Allocator) void = @ptrCast(@alignCast(deinit_ptr_raw));
            var i: usize = 0;
            while (i < self.data.items.len) : (i += self.desc.size) {
                deinit_ptr(&self.data.items[i], allocator);
            }
        }
        self.data.deinit(allocator);
    }

    pub fn allocate(self: *List, allocator: std.mem.Allocator, comptime T: type, n: usize) !void {
        std.debug.assert(self.desc.id == ecs.typeId(T));

        if (comptime @sizeOf(T) == 0) {
            self.data.items.len += n;
        } else {
            try self.data.appendNTimes(allocator, 0, @sizeOf(T) * n);
        }
    }

    pub fn append(self: *List, allocator: std.mem.Allocator, comptime T: type, component: T) !void {
        std.debug.assert(self.desc.id == ecs.typeId(T));
        if (comptime @sizeOf(T) == 0) {
            self.data.items.len += 1;
            return;
        }

        const data: [*]const u8 = @ptrCast(@alignCast(&component));
        try self.data.appendSlice(allocator, data[0..@sizeOf(T)]);
    }

    pub fn appendRaw(self: *List, allocator: std.mem.Allocator, component: []const u8) !void {
        std.debug.assert(component.len == self.desc.size);
        try self.data.appendSlice(allocator, component);
    }

    pub fn appendEmpty(self: *List, allocator: std.mem.Allocator) !void {
        if (self.desc.size == 0) {
            self.data.items.len += 1;
            return;
        }
        try self.data.appendNTimes(allocator, 0, self.desc.size);
    }

    pub fn swapRemove(self: *List, index: usize) void {
        var i = self.desc.size;
        if (i == 0)
            self.data.items.len -= 1;

        while (i > 0) {
            i -= 1;
            _ = self.data.swapRemove(index * self.desc.size + i);
        }
    }

    pub fn deinitComponent(self: *List, gpa: std.mem.Allocator, index: usize) void {
        if (self.desc.deinit) |deinit_ptr| {
            const deinit_fn: *const fn (*anyopaque, std.mem.Allocator) void = @ptrCast(@alignCast(deinit_ptr));
            deinit_fn(@ptrCast(self.getSingleRaw(index).ptr), gpa);
        }
    }

    pub fn get(self: *const List, comptime T: type) []const T {
        std.debug.assert(self.desc.id == ecs.typeId(T));
        return @as([*]const T, @ptrCast(@alignCast(self.data.items.ptr)))[0..self.count()];
    }

    pub fn getMut(self: *const List, comptime T: type) []T {
        std.debug.assert(self.desc.id == ecs.typeId(T));
        return @as([*]T, @ptrCast(@alignCast(self.data.items.ptr)))[0..self.count()];
    }

    pub fn getSingleRaw(self: *const List, index: usize) []u8 {
        const start = index * self.desc.size;
        const end = start + self.desc.size;
        std.debug.assert(end <= self.data.items.len);
        return @as([*]u8, @ptrCast(@alignCast(self.data.items.ptr)))[start..end];
    }

    pub fn count(self: *const List) usize {
        if (self.desc.size > 1) {
            return self.data.items.len / self.desc.size;
        } else {
            return self.data.items.len;
        }
    }
};

pub const Description = struct {
    size: usize,
    alignment: u16,
    id: ecs.TypeId,
    deinit: ?*const anyopaque,

    pub fn get(comptime T: type) Description {
        comptime var deinit_ptr: ?*const anyopaque = null;

        if (@typeInfo(T) == .@"struct" and @hasDecl(T, "deinit")) {
            const fn_type = @typeInfo(@TypeOf(T.deinit));
            if (fn_type != .@"fn") @compileError("deinit is not a function");
            if (fn_type.@"fn".params.len != 2 or
                fn_type.@"fn".params[0].type.? != *T or
                fn_type.@"fn".params[1].type.? != std.mem.Allocator) @compileError("deinit has not the signature \"fn deinit(*type, Allocator) void\"");

            deinit_ptr = @ptrCast(&@field(T, "deinit"));
        }

        return .{
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .id = ecs.typeId(T),
            .deinit = deinit_ptr,
        };
    }
};

// ----------- Test ----------------
test "Basic" {
    const Position = struct { x: i32, y: i32, z: i32 };
    const allocator = std.testing.allocator;

    var list = List.init(Description.get(Position));
    defer list.deinit(allocator);

    const a = Position{ .x = 12, .y = -42, .z = 1 };
    const b = Position{ .x = 13, .y = -44, .z = 1 };

    try list.append(allocator, Position, a);
    try list.append(allocator, Position, b);

    var values = list.getMut(Position);
    try std.testing.expect(values.len == 2);
    try std.testing.expectEqual(a, values[0]);
    try std.testing.expectEqual(b, values[1]);

    values[0].z = -7;

    values = list.getMut(Position);
    try std.testing.expect(values.len == 2);
    try std.testing.expectEqual(Position{ .x = 12, .y = -42, .z = -7 }, values[0]);
    try std.testing.expectEqual(b, values[1]);
}

test "Zero sized types" {
    const Tag = struct {};
    const allocator = std.testing.allocator;

    var list = List.init(Description.get(Tag));
    defer list.deinit(allocator);

    try list.append(allocator, Tag, .{});
    try list.append(allocator, Tag, .{});

    const values = list.getMut(Tag);
    try std.testing.expectEqual(2, values.len);
    try std.testing.expectEqual(Tag{}, values[0]);
    try std.testing.expectEqual(Tag{}, values[1]);
}

const TestComponent = struct {
    test_mem: *usize,
    deinit_called: *bool,

    pub fn init(deinit_called: *bool, gpa: std.mem.Allocator) !TestComponent {
        return TestComponent{
            .test_mem = try gpa.create(usize),
            .deinit_called = deinit_called,
        };
    }

    pub fn deinit(self: *TestComponent, gpa: std.mem.Allocator) void {
        gpa.destroy(self.test_mem);
        self.deinit_called.* = true;
    }
};

test "deinit components" {
    const gpa = std.testing.allocator;

    var deinit_called = false;

    var list = List.init(Description.get(TestComponent));
    defer list.deinit(gpa);

    try list.append(gpa, TestComponent, try .init(&deinit_called, gpa));
    try std.testing.expect(!deinit_called);
    list.deinitComponent(gpa, 0);
    list.swapRemove(0);
    try std.testing.expect(deinit_called);
}
