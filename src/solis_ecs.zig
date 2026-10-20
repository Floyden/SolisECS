pub const Archetype = @import("ecs/Archetype.zig");
pub const ComponentDesc = @import("ecs/components.zig").Description;
pub const ComponentList = @import("ecs/components.zig").List;
pub const Commands = @import("ecs/Commands.zig");
pub const Entity = @import("ecs/Entity.zig");
pub const Schedule = @import("ecs/Schedule.zig");
pub const Global = @import("ecs/global.zig").Global;
pub const Storage = @import("ecs/Storage.zig");
pub const System = @import("ecs/System.zig").System;
pub const SystemDesc = @import("ecs/System.zig").SystemDesc;
pub const Pair = @import("ecs/pairs.zig").Pair;
pub const PairStorage = @import("ecs/pairs.zig").Storage;
pub const TraverseDesc = @import("ecs/pairs.zig").TraverseDesc;
pub const World = @import("ecs/World.zig");

const filters = @import("ecs/filters.zig");
pub const Changed = filters.Changed;
pub const Or = filters.Or;

pub const typeId = @import("ecs/type_id.zig").typeId;
pub const TypeId = @import("ecs/type_id.zig").TypeId;

const query_mod = @import("ecs/query.zig");
pub const Query = query_mod.Query;
pub const QueryIter = query_mod.Iter;

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
