const std = @import("std");

const TypeId = struct {
    id: [:0]const u8,

    fn get(comptime T: type) TypeId {
        return .{ .id = @typeName(T) };
    }
};

const TermFilter = union(enum) {
    none: void,
    _with: TypeId, // Filters entities which have the specified Component
    _without: TypeId, // Filters entities which do not have the specified Component
    _changed: TypeId, // Filters entities where the component might have changed since the last iteration

    fn with(comptime T: type) TermFilter {
        return TermFilter{ ._with = TypeId.get(T) };
    }

    fn without(comptime T: type) TermFilter {
        return TermFilter{ ._without = TypeId.get(T) };
    }
};

const TermAccessFlags = enum {
    InOut, // Componnent is read/write (Default)
    In, // Component is readonly
    Out, // Component is writeonly
    None, // Component is neither written to or read from (i.e. Tags)
};

const TermComponentTarget = enum(u8) {
    Self = 0x1, // Match self
    Parent = 0x2,
    Recursive = 0x4,
};

const TermComponentFlags = struct {
    access: TermAccessFlags = TermAccessFlags.InOut,
    filter: TermFilter = TermFilter.none,
    target: TermComponentTarget = TermComponentTarget.Self,
    singleton: bool = false,
};

const TermComponent = struct {
    id: TypeId,
    flags: TermComponentFlags,
};

// [TODO]: Handle Optionals (?Component)
const Term = union(enum) {
    _empty: void,
    _entity: void,
    _component: TermComponent,
    _filter: TermFilter,
    _scopeStart: void,
    _scopeEnd: void,

    // Create a term to query the component T. The resulting query will assume the
    fn component(comptime T: type, flags: TermComponentFlags) Term {
        return Term{ ._component = TermComponent{ .id = TypeId.get(T), .flags = flags } };
    }

    fn empty() Term {
        return Term._empty;
    }

    fn entity() Term {
        return Term._entity;
    }

    fn with(comptime T: type) Term {
        return Term{ ._filter = TermFilter.with(T) };
    }

    fn without(comptime T: type) Term {
        return Term{ ._filter = TermFilter.without(T) };
    }

    fn startScope() Term {
        return Term._scopeStart;
    }
    fn endScope() Term {
        return Term._scopeEnd;
    }
};

// const Term = struct { id: TypeId, isSingleton: bool = false };
const MAX_TERMS: u32 = 32;
const Query = struct {
    terms: [MAX_TERMS]Term = .{Term.empty()} ** MAX_TERMS,
    fn new(terms: []const Term) Query {
        std.debug.assert(terms.len < MAX_TERMS);

        var res = Query{};
        for (terms, 0..) |src, i| {
            res.terms[i] = src;
        }
        return res;
    }
};

test "basic query" {
    const Position = struct {};
    const Velocity = struct {};
    const Player = struct {};

    _ = Query.new(&.{
        Term.component(Position, .{}),
        Term.component(Velocity, .{ .access = TermAccessFlags.In }), // Velocity is const
        Term.component(?Player, .{}), // Do something to Player if present
    });
}

test "basic entity query" {
    const Position = struct {};
    const Velocity = struct {};

    _ = Query.new(&.{
        Term.entity(), // Add Entity information
        Term.component(Position, .{}),
        Term.component(Velocity, .{ .access = TermAccessFlags.In }),
    });
}

test "singleton query" {
    const Gravity = struct {};
    const Velocity = struct {};

    _ = Query.new(&.{
        Term.component(Velocity, .{}),
        Term.component(Gravity, .{ .singleton = true }),
    });
}

test "hierachy" {
    const Position = struct {};
    const Local = struct {};
    const World = struct {};

    _ = Query.new(&.{
        Term.component(Position, .{ .filter = TermFilter.with(Local) }), // Local position relative to parent
        Term.component(?Position, .{ .filter = TermFilter.with(World), .target = TermComponentTarget.Parent }), // World position of parent
        Term.component(Position, .{ .filter = TermFilter.with(World) }), // World position result
    });
}

test "Find Object filtered" {
    const Object = struct {};
    const Position = struct {};
    const Location = struct {};

    // Find all objects without a position or location
    _ = Query.new(&.{
        Term.component(Object, .{}),
        Term.startScope(), // Not Scope
        Term.with(Position), // Add or operator
        Term.with(Location),
        Term.endScope(),
    });
}

test "Find children without position" {
    const Position = struct {};
    // const Position = struct {};
    // const Location = struct {};

    // Find all entities that do not have children with position
    _ = Query.new(&.{
        Term.component(Position, .{}),
    });
    // Find all entities that have a child without position
}
