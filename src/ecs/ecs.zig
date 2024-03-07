const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Entity = struct { id: usize };

const ComponentDesc = struct {
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
    entities: ArrayList(Entity),

    pub fn init(allocator: Allocator) World {
        return World{
            .allocator = allocator,
            .components = ArrayList(ComponentDesc).init(allocator),
            .systems = ArrayList(SystemDesc).init(allocator),
            .entities = ArrayList(Entity).init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        for (self.systems.items) |system| {
            system.params.deinit();
        }
        self.systems.deinit();
        self.components.deinit();
        self.entities.deinit();
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
        try self.entities.append(Entity{ .id = self.entities.items.len });
        return self.entities.getLast();
    }

    pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) void {
        _ = entity;
        _ = arg;
        _ = self;
    }

    pub fn get(self: *World, entity: Entity, comptime T: type) ?T {
        _ = entity;
        _ = self;
        return null;
    }
};
