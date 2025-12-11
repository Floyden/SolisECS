const std = @import("std");
const Storage = @import("storage.zig").Storage;
const iter = @import("iter.zig");
pub const Iter = iter.Iter;
pub const Query = iter.Query;
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

pub const World = struct {
    allocator: Allocator,
    components: ArrayList(ComponentDesc),
    systems: ArrayList(SystemDesc),
    maxEnt: usize,
    storage: Storage,

    pub fn init(allocator: Allocator) World {
        return World{
            .allocator = allocator,
            .components = .empty,
            .systems = .empty,
            .maxEnt = 1,
            .storage = Storage.init(allocator) catch unreachable,
        };
    }

    pub fn deinit(self: *World) void {
        for (self.systems.items) |*system| {
            system.params.deinit(self.allocator);
        }
        self.systems.deinit(self.allocator);
        self.components.deinit(self.allocator);
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

    pub fn step(self: *World) !void {
        for (self.systems.items) |*system| {
            var query = try Query.init(self.allocator, self, system.params.items);
            lArc: for (self.storage.archetypes.items) |*archetype| {
                for (system.params.items) |param| {
                    if (!archetype.hasType(param)) continue :lArc;
                }
                try query.addArchetype(archetype);
            }
            for (0..query.archetypes.items.len) |i| {
                var it = query.iter(i);
                system.callback(&it);
            }
        }
    }

    pub fn create(self: *World) !Entity {
        defer self.maxEnt += 1;
        return self.storage.addEntity(Entity{ .id = self.maxEnt });
    }

    pub fn set(self: *World, entity: Entity, comptime T: type, arg: T) !void {
        try self.storage.setComponents(entity, T, arg);
    }

    pub fn get(self: *World, entity: Entity, comptime T: type) ?*const T {
        return self.storage.get(T, entity);
    }

    pub fn getMut(self: *World, entity: Entity, comptime T: type) ?*T {
        return self.storage.getMut(T, entity);
    }
};
