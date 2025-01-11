const std = @import("std");
const rl = @import("raylib");
const events = @import("events");

const TileIndex = struct {
    const none = TileIndex{ .x = std.math.maxInt(u32), .y = std.math.maxInt(u32) };

    x: u32,
    y: u32,

    pub fn new(x: u32, y: u32) TileIndex {
        return .{ .x = x, .y = y };
    }

    pub fn is_none(self: TileIndex) bool {
        return std.meta.eql(self, TileIndex.none);
    }
};

const TileSet = struct {
    width: i32,
    height: i32,
    columns: u32,
    image: rl.Image,
    texture: rl.Texture2D,

    fn init_from_path(width: i32, height: i32, path: [:0]const u8) TileSet {
        const image = rl.loadImage(path);
        const texture = rl.loadTextureFromImage(image);
        const columns: u32 = @intCast(@divFloor(image.width, width));
        return TileSet{ .width = width, .height = height, .columns = columns, .image = image, .texture = texture };
    }

    fn deinit(self: TileSet) void {
        rl.unloadTexture(self.texture);
        rl.unloadImage(self.image);
    }

    fn drawTile(self: TileSet, index: TileIndex, posX: f32, posY: f32) void {
        const row: f32 = @floatFromInt(index.y);
        const column: f32 = @floatFromInt(index.x);
        const width: f32 = @floatFromInt(self.width);
        const height: f32 = @floatFromInt(self.height);
        rl.drawTextureRec(
            self.texture,
            rl.Rectangle{ .x = column * width, .y = row * height, .width = width, .height = height },
            rl.Vector2{ .x = posX, .y = posY },
            rl.Color.white,
        );
    }
};

const Field = struct {
    const LAYER_COUNT: i32 = 2;
    width: i32,
    height: i32,
    tile_set: TileSet,
    tiles: [LAYER_COUNT]std.ArrayList(TileIndex),
    size: f32,

    pub fn init(width: i32, height: i32, tile_set: TileSet, allocator: std.mem.Allocator) !Field {
        var tiles: [LAYER_COUNT]std.ArrayList(TileIndex) = undefined;
        for (&tiles) |*layer| {
            layer.* = std.ArrayList(TileIndex).init(allocator);
            layer.appendNTimes(TileIndex.none, @intCast(width * height)) catch unreachable;
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

    pub fn fillAll(self: *Field, layer: usize, tile: TileIndex) void {
        std.debug.assert(layer < LAYER_COUNT);
        for (self.tiles[layer].items) |*t| {
            t.* = tile;
        }
    }

    pub fn getTileMut(self: *Field, layer: usize, x: i32, y: i32) *TileIndex {
        std.debug.assert(x < self.width and y < self.height);
        return &self.tiles[layer].items[@as(usize, @intCast(x + y * self.width))];
    }

    pub fn render(self: Field, posX: i32, posY: i32) void {
        const pos_x: f32 = @floatFromInt(posX);
        const pos_y: f32 = @floatFromInt(posY);
        for (0..LAYER_COUNT) |layer| {
            var pos: f32 = 0.0;
            for (self.tiles[layer].items) |tile| {
                defer pos += 1.0;
                if (tile.is_none()) continue;

                const width: f32 = @floatFromInt(self.width);
                const x: f32 = @mod(pos, width);
                const y: f32 = @divTrunc(pos, width);

                self.tile_set.drawTile(tile, pos_x + x * 16.0, pos_y + y * 16.0);
            }
        }
    }

    pub fn drawCursor(self: Field, x: i32, y: i32) void {
        const posX: f32 = @floatFromInt(x);
        const posY: f32 = @floatFromInt(y);
        rl.drawRectangleLinesEx(rl.Rectangle{ .x = posX * self.size, .y = posY * self.size, .width = self.size, .height = self.size }, 1.0, rl.Color.black);
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

const KeyboardState = struct {
    pressed: std.AutoHashMap(rl.KeyboardKey, ?void),

    pub fn init(allocator: std.mem.Allocator) KeyboardState {
        return .{ .pressed = std.AutoHashMap(rl.KeyboardKey, ?void).init(allocator) };
    }

    pub fn deinit(self: *KeyboardState) void {
        self.pressed.deinit();
    }
};

const KeyInput = struct {
    key: rl.KeyboardKey,
    pressed: bool,
};

pub fn handleInputEvents(keyboard: *KeyboardState, writer: events.EventWriter(KeyInput)) void {
    var key = rl.getKeyPressed();
    while (key != rl.KeyboardKey.null) : (key = rl.getKeyPressed()) {
        keyboard.pressed.put(key, null) catch unreachable;
        writer.write(KeyInput{ .key = key, .pressed = true }) catch unreachable;
    }
}

pub fn playerInput(reader: *events.EventReader(KeyInput), cursor: *FieldCursor) void {
    while (reader.next()) |event| {
        switch (event.key) {
            rl.KeyboardKey.d => {
                if (cursor.pos[0] < cursor.field.width)
                    cursor.pos[0] += 1;
            },
            rl.KeyboardKey.a => {
                if (cursor.pos[0] > 0)
                    cursor.pos[0] -= 1;
            },
            rl.KeyboardKey.s => {
                if (cursor.pos[1] < cursor.field.height)
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

pub fn main() !void {
    rl.initWindow(800, 600, "Hi");
    defer rl.closeWindow();

    const canvasLayers = [_]rl.RenderTexture2D{ rl.loadRenderTexture(200, 150), rl.loadRenderTexture(200, 150) };
    defer for (canvasLayers) |layer| layer.unload();

    rl.setTextureFilter(canvasLayers[0].texture, rl.TextureFilter.point);

    const tileset = TileSet.init_from_path(16, 16, "examples/resources/tileset.png");
    defer tileset.deinit();

    var field = Field.init(5, 5, tileset, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    field.getTileMut(0, 0, 0).* = TileIndex.new(2, 0);
    field.getTileMut(0, 1, 0).* = TileIndex.new(0, 0);
    field.getTileMut(0, 0, 1).* = TileIndex.new(2, 1);
    field.getTileMut(0, 1, 1).* = TileIndex.new(0, 1);
    field.getTileMut(0, 0, 2).* = TileIndex.new(2, 1);
    field.getTileMut(0, 1, 2).* = TileIndex.new(0, 1);
    field.getTileMut(0, 0, 3).* = TileIndex.new(2, 2);
    field.getTileMut(0, 1, 3).* = TileIndex.new(0, 2);

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

        playerInput(&reader, &cursor);

        canvasLayers[0].begin();

        rl.clearBackground(rl.Color.white);

        field.render(0, 0);
        canvasLayers[0].end();
        canvasLayers[1].begin();
        rl.clearBackground(rl.Color.fromInt(0));
        cursor.render();
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
