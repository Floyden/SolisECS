const std = @import("std");
const rl = @import("raylib");
const solis = @import("solis");

pub const KeyboardState = struct {
    pressed: std.AutoHashMap(rl.KeyboardKey, ?void),

    pub fn init(allocator: std.mem.Allocator) KeyboardState {
        return .{ .pressed = std.AutoHashMap(rl.KeyboardKey, ?void).init(allocator) };
    }

    pub fn deinit(self: *KeyboardState) void {
        self.pressed.deinit();
    }
};

pub const KeyInput = struct {
    key: rl.KeyboardKey,
    pressed: bool,
};

pub fn handleInputEvents(keyboard: *KeyboardState, writer: solis.events.EventWriter(KeyInput)) void {
    var key = rl.getKeyPressed();
    while (key != rl.KeyboardKey.null) : (key = rl.getKeyPressed()) {
        keyboard.pressed.put(key, null) catch unreachable;
        writer.write(KeyInput{ .key = key, .pressed = true }) catch unreachable;
    }
}
