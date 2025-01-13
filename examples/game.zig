const std = @import("std");
const solis = @import("solis");
const rl = solis.raylib;
const events = solis.events;
const KeyInput = solis.input.KeyInput;
const KeyboardState = solis.input.KeyboardState;
const handleInputEvents = solis.input.keyboard.handleInputEvents;
const TextureAtlas = solis.TextureAtlas;

const Field = struct {
    const LAYER_COUNT: i32 = 2;
    width: i32,
    height: i32,
    tile_set: solis.TextureAtlas,
    tiles: [LAYER_COUNT]std.ArrayList(TextureAtlas.Index),
    size: f32,

    pub fn init(width: i32, height: i32, tile_set: TextureAtlas, allocator: std.mem.Allocator) !Field {
        var tiles: [LAYER_COUNT]std.ArrayList(TextureAtlas.Index) = undefined;
        for (&tiles) |*layer| {
            layer.* = std.ArrayList(TextureAtlas.Index).init(allocator);
            layer.appendNTimes(TextureAtlas.Index.none, @intCast(width * height)) catch unreachable;
        }

        return Field{
            .width = width,
            .height = height,
            .tile_set = tile_set,
            .tiles = tiles,
            .size = @floatFromInt(tile_set.width),
        };
    }

    pub fn deinit(self: *Field) void {
        for (self.tiles) |layer| layer.deinit();
    }

    pub fn fillAll(self: *Field, layer: usize, tile: TextureAtlas.Index) void {
        std.debug.assert(layer < LAYER_COUNT);
        for (self.tiles[layer].items) |*t| {
            t.* = tile;
        }
    }

    pub fn getTileMut(self: *Field, layer: usize, x: i32, y: i32) *TextureAtlas.Index {
        std.debug.assert(x < self.width and y < self.height);
        return &self.tiles[layer].items[@as(usize, @intCast(x + y * self.width))];
    }

    pub fn render_layer(self: Field, layer: usize, posX: i32, posY: i32) void {
        const pos_x: f32 = @floatFromInt(posX);
        const pos_y: f32 = @floatFromInt(posY);

        var pos: f32 = 0.0;
        for (self.tiles[layer].items) |tile| {
            defer pos += 1.0;
            if (tile == TextureAtlas.Index.none) continue;

            const width: f32 = @floatFromInt(self.width);
            const x: f32 = @mod(pos, width);
            const y: f32 = @divTrunc(pos, width);

            self.tile_set.drawTile(tile, pos_x + x * 16.0, pos_y + y * 16.0);
        }
    }

    pub fn drawCursor(self: Field, x: i32, y: i32) void {
        const posX: f32 = @floatFromInt(x);
        const posY: f32 = @floatFromInt(y);
        rl.drawRectangleLinesEx(rl.Rectangle{ .x = posX * self.size, .y = posY * self.size, .width = self.size, .height = self.size }, 1.0, rl.Color.black);
    }
};

const AnimationType = enum {
    Loop,
    PlayOnce,
    PlayOnceReset,
};

const Animation = struct {
    current_frame: u32,
    total_frames: u32,
    current_time: f32,
    frame_time: f32,
    playing: bool,
    animation_type: AnimationType,

    pub fn new(frames: u32, frame_time: f32, animation_type: AnimationType) Animation {
        return .{ .current_frame = 0, .total_frames = frames, .current_time = 0.0, .frame_time = frame_time, .playing = false, .animation_type = animation_type };
    }

    pub fn currentFrame(self: Animation) u32 {
        return self.current_frame;
    }

    pub fn play(self: *Animation) void {
        self.playing = true;
    }

    pub fn reset(self: *Animation) void {
        self.current_frame = 0;
        self.current_time = 0;
    }

    pub fn update(self: *Animation, time: f32) void {
        if (!self.playing) return;
        self.current_time += time;
        if (self.current_time <= self.frame_time) return;

        self.current_time -= self.frame_time;
        if (self.current_frame < self.total_frames - 1) {
            self.current_frame += 1;
            return;
        }

        switch (self.animation_type) {
            AnimationType.Loop => self.current_frame = 0,
            AnimationType.PlayOnce => self.playing = false,
            AnimationType.PlayOnceReset => {
                self.playing = false;
                self.current_frame = 0;
            },
        }
    }
};

const FieldCursor = struct {
    pos: [2]i32,
    selection: ?[2]i32,
    field: *Field,

    pub fn new(field: *Field) FieldCursor {
        return .{ .pos = [_]i32{ 0, 0 }, .selection = null, .field = field };
    }

    pub fn render(self: FieldCursor) void {
        const size = self.field.size;

        if (self.selection) |select| {
            const selectX: f32 = @floatFromInt(select[0]);
            const selectY: f32 = @floatFromInt(select[1]);
            rl.drawRectangleLinesEx(rl.Rectangle{ .x = selectX * size, .y = selectY * size, .width = size, .height = size }, 1.0, rl.Color.green);
        }
        const posX: f32 = @floatFromInt(self.pos[0]);
        const posY: f32 = @floatFromInt(self.pos[1]);
        rl.drawRectangleLinesEx(rl.Rectangle{ .x = posX * size, .y = posY * size, .width = size, .height = size }, 1.0, rl.Color.black);
    }
};

pub fn playerInput(reader: *events.EventReader(KeyInput), cursor: *FieldCursor) void {
    while (reader.next()) |event| {
        switch (event.key) {
            rl.KeyboardKey.d => {
                if (cursor.pos[0] < cursor.field.width - 1)
                    cursor.pos[0] += 1;
            },
            rl.KeyboardKey.a => {
                if (cursor.pos[0] > 0)
                    cursor.pos[0] -= 1;
            },
            rl.KeyboardKey.s => {
                if (cursor.pos[1] < cursor.field.height - 1)
                    cursor.pos[1] += 1;
            },
            rl.KeyboardKey.w => {
                if (cursor.pos[1] > 0)
                    cursor.pos[1] -= 1;
            },
            rl.KeyboardKey.space => {
                if (cursor.selection) |pos| {
                    const src_tile = cursor.field.getTileMut(0, pos[0], pos[1]);
                    if (!std.mem.eql(i32, &pos, &cursor.pos)) {
                        const dest = cursor.field.getTileMut(0, cursor.pos[0], cursor.pos[1]);
                        dest.* = src_tile.*;
                    }

                    // Do something with cursor
                    cursor.selection = null;
                } else {
                    cursor.selection = cursor.pos;
                }
            },
            else => {},
        }
    }
}

pub fn updateCharacter(reader: *events.EventReader(KeyInput), animation: [*]Animation, current_animation: *usize, time: f32) void {
    var reset = false;
    while (reader.next()) |event| {
        switch (event.key) {
            rl.KeyboardKey.one => {
                current_animation.* = 1;
                reset = true;
            },
            rl.KeyboardKey.two => {
                current_animation.* = 2;
                reset = true;
            },
            rl.KeyboardKey.three => {
                current_animation.* = 3;
                reset = true;
            },
            rl.KeyboardKey.four => {
                current_animation.* = 4;
                reset = true;
            },
            else => {},
        }
    }

    if (!reset and !animation[current_animation.*].playing) {
        current_animation.* = 0;
        reset = true;
    }
    if (reset) {
        animation[current_animation.*].reset();
        animation[current_animation.*].play();
    }
    animation[current_animation.*].update(time);
}

pub fn main() !void {
    rl.initWindow(800, 600, "Hi");
    defer rl.closeWindow();

    const canvasLayers = [_]rl.RenderTexture2D{ rl.loadRenderTexture(200, 150), rl.loadRenderTexture(200, 150) };
    defer for (canvasLayers) |layer| layer.unload();

    rl.setTextureFilter(canvasLayers[0].texture, rl.TextureFilter.point);

    const tileset = TextureAtlas.init_from_path(16, 16, "examples/resources/tileset.png");
    defer tileset.deinit();

    var animations = [_]Animation{
        Animation.new(6, 0.1, AnimationType.Loop),
        Animation.new(8, 0.1, AnimationType.PlayOnce),
        Animation.new(6, 0.1, AnimationType.PlayOnceReset),
        Animation.new(6, 0.1, AnimationType.PlayOnceReset),
        Animation.new(9, 0.1, AnimationType.PlayOnceReset),
    };
    var current_animation: usize = 0;
    animations[current_animation].play();
    _ = &current_animation;

    const character = TextureAtlas.init_from_path(100, 100, "examples/resources/Soldier.png");
    defer character.deinit();

    var field = Field.init(5, 5, tileset, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    const tiles = [_]u32{
        2, 0, 0, 0, 1, 0, 1, 0, 1, 0, //
        2, 1, 0, 1, 1, 1, 1, 1, 1, 1, //
        2, 1, 0, 1, 1, 1, 1, 1, 1, 1, //
        2, 2, 0, 2, 1, 2, 1, 2, 4, 0, //
        1, 0, 1, 0, 1, 0, 1, 0, 4, 1, //
    };
    var i: i32 = 0;
    while (i < tiles.len) : (i += 2) {
        field.getTileMut(0, @mod(i >> 1, field.width), @divTrunc(i >> 1, field.width)).* = tileset.indexAt(tiles[@intCast(i)], tiles[@intCast(i + 1)]);
    }

    var cursor = FieldCursor.new(&field);
    var keyboardState = KeyboardState.init(std.heap.page_allocator);
    defer keyboardState.deinit();
    var keyEvents = events.Events(KeyInput).init(std.heap.page_allocator);
    defer keyEvents.deinit();

    var charReader = keyEvents.reader();
    var reader = keyEvents.reader();
    const writer = keyEvents.writer();

    rl.setTargetFPS(30);
    while (!rl.windowShouldClose()) {
        handleInputEvents(&keyboardState, writer);
        updateCharacter(&charReader, &animations, &current_animation, rl.getFrameTime());

        playerInput(&reader, &cursor);

        for (0..Field.LAYER_COUNT) |layer| {
            canvasLayers[layer].begin();
            rl.clearBackground(rl.Color.white);
            field.render_layer(layer, 0, 0);

            canvasLayers[layer].end();
        }

        canvasLayers[1].begin();
        rl.clearBackground(rl.Color.fromInt(0));
        cursor.render();
        const current_frame = character.indexAt(animations[current_animation].currentFrame(), @intCast(current_animation));
        character.drawTile(current_frame, -42, -42 + 16);
        canvasLayers[1].end();
        rl.beginDrawing();
        for (canvasLayers) |canvas| {
            rl.drawTexturePro(
                canvas.texture,
                rl.Rectangle{ .x = 0.0, .y = 0.0, .width = @floatFromInt(canvas.texture.width), .height = @floatFromInt(-canvas.texture.height) },
                rl.Rectangle{ .x = 0.0, .y = 0.0, .width = 800, .height = 600 },
                rl.Vector2{ .x = 0.0, .y = 0.0 },
                0.0,
                rl.Color.white,
            );
        }
        rl.endDrawing();
    }
}
