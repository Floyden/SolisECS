const std = @import("std");
const Storage = @import("storage.zig").Storage;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Entity = struct { id: usize };

pub const ComponentDesc = struct {
    size: usize,
    alignment: usize,
    name: [:0]const u8,
};

const SystemDesc = struct {
    callback: *const fn (*Iter) void,
    params: ArrayList([:0]const u8),
};

pub const Iter = struct {
    world: *World,
    components: [][]anyopaque,
    count: usize,

    pub fn getFieldMut(self: *Iter, comptime T: type, loc: usize) [*]T {
        return @as([*]T, @alignCast(@ptrCast(self.components[loc])));
    }

    pub fn getField(self: *Iter, comptime T: type, loc: usize) [*]const T {
        return @as([*]T, @alignCast(@ptrCast(self.components[loc])));
    }
};

pub const World = struct {
    allocator: Allocator,
    components: ArrayList(ComponentDesc),
    systems: ArrayList(SystemDesc),
    maxEnt: usize,
    storage: Storage,

    pub fn init(allocator: Allocator) World {
        return World{
            .allocator = allocator,
            .components = ArrayList(ComponentDesc).init(allocator),
            .systems = ArrayList(SystemDesc).init(allocator),
            .maxEnt = 1,
            .storage = Storage.init(allocator) catch unreachable,
        };
    }

    pub fn deinit(self: *World) void {
        for (self.systems.items) |system| {
            system.params.deinit();
        }
        self.systems.deinit();
        self.components.deinit();
        self.storage.deinit();
    }

    // [TODO] implement
    pub fn register(self: *World, comptime args: anytype) !void {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);

        const field_info = args_type_info.Struct.fields;
        inline for (0..field_info.len) |i| {
            const field = @field(args, field_info[i].name);
            try self.components.append(ComponentDesc{ .size = @sizeOf(field), .alignment = @alignOf(field), .name = @typeName(field) });
        }
    }

    // [TODO] figure out how to store the parameter types
    pub fn addSystem(self: *World, callback: fn (*Iter) void, comptime args: anytype) !void {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);

        const field_info = args_type_info.Struct.fields;
        var desc = SystemDesc{ .callback = callback, .params = undefined };
        desc.params = ArrayList([:0]const u8).init(self.allocator);

        inline for (0..field_info.len) |i| {
            const field = @field(args, field_info[i].name);
            try desc.params.append(@typeName(field));
        }

        try self.systems.append(desc);
    }

    pub fn step(self: *World) void {
        _ = self;
    }

    pub fn create(self: *World) !Entity {
        defer self.maxEnt += 1;
        return self.storage.addEntity(Entity{ .id = self.maxEnt });
    }

    pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !void {
        try self.storage.setComponents(entity, T, arg);
    }

    pub fn get(self: *World, entity: Entity, comptime T: type) ?T {
        _ = entity;
        _ = self;
        return null;
    }
};
