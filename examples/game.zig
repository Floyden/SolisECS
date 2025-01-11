const std = @import("std");
const rl = @import("raylib");
const events = @import("events");

const TileType = enum(u8) {
    Empty,
    Grass,
    Road,
    Object,

    pub fn asChar(self: TileType) u8 {
        switch (self) {
            TileType.Empty => return ' ',
            TileType.Grass => return '#',
            TileType.Road => return '=',
            TileType.Object => return 'X',
        }
    }
};

const Tile = struct {
    type: TileType,
    color: rl.Color,

    pub fn new(tile_type: TileType, color: rl.Color) Tile {
        return Tile{ .type = tile_type, .color = color };
    }
};

const Field = struct {
    const LAYER_COUNT: i32 = 2;
    width: i32,
    height: i32,
    tiles: [LAYER_COUNT]std.ArrayList(Tile),
    size: f32,

    pub fn init(width: i32, height: i32, allocator: std.mem.Allocator) !Field {
        var tiles: [LAYER_COUNT]std.ArrayList(Tile) = undefined;
        for (&tiles) |*layer| {
            layer.* = std.ArrayList(Tile).init(allocator);
            layer.appendNTimes(Tile.new(TileType.Empty, rl.Color.white), @intCast(width * height)) catch unreachable;
        }

        return Field{
            .width = width,
            .height = height,
            .tiles = tiles,
            .size = @floatFromInt(rl.getFontDefault().baseSize),
        };
    }

    pub fn deinit(self: *Field) void {
        for (self.tiles) |layer| layer.deinit();
    }

    pub fn fillAll(self: *Field, layer: usize, tile: Tile) void {
        std.debug.assert(layer < LAYER_COUNT);
        for (self.tiles[layer].items) |*t| {
            t.* = tile;
        }
    }

    pub fn getTileMut(self: *Field, layer: usize, x: i32, y: i32) *Tile {
        std.debug.assert(x < self.width and y < self.height);
        return &self.tiles[layer].items[@as(usize, @intCast(x + y * self.width))];
    }

    pub fn render(self: Field, posX: i32, posY: i32) void {
        const pos_x: f32 = @floatFromInt(posX);
        const pos_y: f32 = @floatFromInt(posY);
        const font = rl.getFontDefault();
        for (0..LAYER_COUNT) |layer| {
            var pos: f32 = 0.0;
            for (self.tiles[layer].items) |tile| {
                defer pos += 1.0;

                const width: f32 = @floatFromInt(self.width);
                const x: f32 = @mod(pos, width);
                const y: f32 = @divTrunc(pos, width);

                const value = tile.type.asChar();
                const offset_x = (self.size - @as(f32, @floatFromInt(font.glyphs[value].image.width))) / 2.0;
                const offset_y = (self.size - @as(f32, @floatFromInt(font.glyphs[value].image.height))) / 2.0;
                rl.drawTextCodepoint(
                    font,
                    value,
                    rl.Vector2{ .x = (pos_x + x) * self.size + offset_x, .y = (pos_y + y) * self.size + offset_y },
                    self.size,
                    tile.color,
                );
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

const KeyInput = struct {
    key: rl.KeyboardKey,
    pressed: bool,
};

pub fn handleInputEvents(writer: events.EventWriter(KeyInput)) void {
    var key = rl.getKeyPressed();
    while (key != rl.KeyboardKey.null) : (key = rl.getKeyPressed())
        writer.write(KeyInput{ .key = key, .pressed = true }) catch unreachable;
}

pub fn playerInput(reader: *events.EventReader(KeyInput), cursor: *FieldCursor) void {
    while (reader.next()) |event| {
        switch (event.key) {
            rl.KeyboardKey.d => cursor.pos[0] += 1,
            rl.KeyboardKey.a => cursor.pos[0] -= 1,
            rl.KeyboardKey.s => cursor.pos[1] += 1,
            rl.KeyboardKey.w => cursor.pos[1] -= 1,
            rl.KeyboardKey.space => {
                if (cursor.selection) |pos| {
                    const src_tile = cursor.field.getTileMut(1, pos[0], pos[1]);
                    if (!std.mem.eql(i32, &pos, &cursor.pos) and src_tile.type == TileType.Object) {
                        const dest = cursor.field.getTileMut(1, cursor.pos[0], cursor.pos[1]);
                        dest.* = src_tile.*;
                        src_tile.type = TileType.Empty;
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

    var field = Field.init(10, 10, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    field.fillAll(0, Tile.new(TileType.Grass, rl.Color.green));
    for (4..6) |y| {
        for (0..6) |x| {
            field.getTileMut(0, @intCast(x), @intCast(y)).* = Tile.new(TileType.Road, rl.Color.yellow);
        }
    }

    for (0..4) |y| {
        for (4..6) |x| {
            field.getTileMut(0, @intCast(x), @intCast(y)).* = Tile.new(TileType.Road, rl.Color.yellow);
        }
    }

    field.getTileMut(1, 1, 0).* = Tile.new(TileType.Object, rl.Color.black);

    var cursor = FieldCursor.new(&field);
    var keyEvents = events.Events(KeyInput).init(std.heap.page_allocator);
    var reader = keyEvents.reader();
    const writer = keyEvents.writer();

    rl.setTargetFPS(30);
    while (!rl.windowShouldClose()) {
        handleInputEvents(writer);

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
