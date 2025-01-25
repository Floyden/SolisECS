const std = @import("std");
const solis = @import("solis");
const rl = solis.raylib;
const events = solis.events;
const KeyInput = solis.input.KeyInput;
const KeyboardState = solis.input.KeyboardState;
const handleInputEvents = solis.input.keyboard.handleInputEvents;
const TextureAtlas = solis.TextureAtlas;
const Animation2D = solis.Animation2D;

const Character = struct {
    const State = enum(u32) {
        Idle = 0,
        Moving,
        Attack1,
        Attack2,
        Attack3,
        _Count,
    };

    position: @Vector(2, f32), // just a single position for now
    destination: ?@Vector(2, f32),
    sprites: TextureAtlas,
    timer: f32,
    state: State,
    next_state: ?State,
    animations: [@intFromEnum(State._Count)]Animation2D,

    fn currentAnimation(self: *Character) *Animation2D {
        return &self.animations[@intFromEnum(self.state)];
    }

    // Transition to the next state
    fn transition(self: *Character) void {
        self.state = if (self.next_state) |next| next else State.Idle;
        self.next_state = null;

        var current_animation = self.currentAnimation();
        current_animation.reset();
        current_animation.play();
    }

    fn queueNext(self: *Character, next: State) void {
        if (self.state != State.Moving and next != State.Moving)
            self.destination = null;
        self.next_state = next;
    }

    fn setDestination(self: *Character, dest: [2]f32) void {
        if (@reduce(.And, dest == self.position)) return;
        self.destination = dest;
        self.queueNext(State.Moving);
    }

    pub fn update(character: *Character, time: f32) void {
        defer character.currentAnimation().update(time);

        const TICK = 60.0 / 100.0;
        character.timer += time;

        if (character.timer < TICK)
            return;
        character.timer -= TICK;

        var transit = true;

        if (character.state == State.Moving and character.destination != null) {
            const diff = character.destination.? - character.position;

            const idx = @intFromBool(@abs(diff[0]) < @abs(diff[1]));
            character.position[idx] += std.math.sign(diff[idx]);

            if (@reduce(.And, character.position == character.destination.?)) {
                character.destination = null;
            } else {
                transit = character.next_state != null;
            }
        }

        if (transit)
            character.transition();
    }
};

const Field = struct {
    const LAYER_COUNT: i32 = 2;
    width: i32,
    height: i32,
    tile_set: solis.TextureAtlas,
    tiles: [LAYER_COUNT]std.ArrayList(TextureAtlas.Index),
    size: f32,
    character: ?Character,

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
            .character = null,
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

    pub fn renderLayer(self: Field, layer: usize, posX: i32, posY: i32) void {
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

const FieldCursor = struct {
    pos: @Vector(2, f32),
    selection: ?*Character,
    field: *Field,

    pub fn new(field: *Field) FieldCursor {
        return .{ .pos = .{ 0.0, 0.0 }, .selection = null, .field = field };
    }

    pub fn render(self: FieldCursor) void {
        const size = self.field.size;

        if (self.selection) |select| {
            rl.drawRectangleLinesEx(rl.Rectangle{ .x = select.position[0] * size, .y = select.position[1] * size, .width = size, .height = size }, 1.0, rl.Color.green);
        }
        const posX: f32 = self.pos[0];
        const posY: f32 = self.pos[1];
        rl.drawRectangleLinesEx(rl.Rectangle{ .x = posX * size, .y = posY * size, .width = size, .height = size }, 1.0, rl.Color.black);
    }
};

pub fn playerInput(reader: *events.EventReader(KeyInput), cursor: *FieldCursor) void {
    while (reader.next()) |event| {
        switch (event.key) {
            rl.KeyboardKey.d => {
                if (cursor.pos[0] < @as(f32, @floatFromInt(cursor.field.width - 1)))
                    cursor.pos[0] += 1;
            },
            rl.KeyboardKey.a => {
                if (cursor.pos[0] > 0)
                    cursor.pos[0] -= 1;
            },
            rl.KeyboardKey.s => {
                if (cursor.pos[1] < @as(f32, @floatFromInt(cursor.field.height - 1)))
                    cursor.pos[1] += 1;
            },
            rl.KeyboardKey.w => {
                if (cursor.pos[1] > 0)
                    cursor.pos[1] -= 1;
            },
            rl.KeyboardKey.space => {
                if (cursor.selection) |character| {
                    character.setDestination(cursor.pos);
                } else if (@reduce(.And, cursor.field.character.?.position == cursor.pos)) {
                    cursor.selection = &cursor.field.character.?;
                }
            },
            rl.KeyboardKey.one => {
                if (cursor.selection) |character|
                    character.queueNext(Character.State.Attack1);
            },
            rl.KeyboardKey.two => {
                if (cursor.selection) |character|
                    character.queueNext(Character.State.Attack2);
            },
            rl.KeyboardKey.three => {
                if (cursor.selection) |character|
                    character.queueNext(Character.State.Attack3);
            },
            else => {},
        }
    }
}

pub fn main() !void {
    rl.initWindow(800, 600, "Hi");
    defer rl.closeWindow();

    const canvasLayers = [_]rl.RenderTexture2D{ rl.loadRenderTexture(200, 150), rl.loadRenderTexture(200, 150) };
    defer for (canvasLayers) |layer| layer.unload();

    rl.setTextureFilter(canvasLayers[0].texture, rl.TextureFilter.point);

    const tileset = TextureAtlas.init_from_path(16, 16, "examples/resources/tileset.png");
    defer tileset.deinit();

    const character = TextureAtlas.init_from_path(100, 100, "examples/resources/Soldier.png");
    defer character.deinit();

    var field = Field.init(5, 5, tileset, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    const animations = [_]Animation2D{
        Animation2D.new(6, 0.1, Animation2D.Type.Loop),
        Animation2D.new(8, 0.6 / 8.0, Animation2D.Type.Loop),
        Animation2D.new(6, 0.1, Animation2D.Type.PlayOnceReset),
        Animation2D.new(6, 0.1, Animation2D.Type.PlayOnceReset),
        Animation2D.new(9, 0.6 / 9.0, Animation2D.Type.PlayOnceReset),
    };

    field.character = Character{
        .position = .{ 0, 1 },
        .destination = null,
        .state = Character.State.Idle,
        .next_state = null,
        .timer = 0.0,
        .sprites = character,
        .animations = animations,
    };

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

    var reader = keyEvents.reader();
    const writer = keyEvents.writer();

    rl.setTargetFPS(30);
    while (!rl.windowShouldClose()) {
        handleInputEvents(&keyboardState, writer);
        field.character.?.update(rl.getFrameTime());

        playerInput(&reader, &cursor);

        for (0..Field.LAYER_COUNT) |layer| {
            canvasLayers[layer].begin();
            rl.clearBackground(rl.Color.white);
            field.renderLayer(layer, 0, 0);

            canvasLayers[layer].end();
        }

        canvasLayers[1].begin();
        rl.clearBackground(rl.Color.fromInt(0));
        cursor.render();
        if (field.character) |*char| {
            const current_frame = char.sprites.indexAt(char.currentAnimation().currentFrame(), @intFromEnum(char.state));
            char.sprites.drawTile(current_frame, -42.0 + char.position[0] * field.size, -42.0 + char.position[1] * field.size);
        }
        canvasLayers[1].end();

        // Render final image
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
