const std = @import("std");
const rl = @import("raylib");
const events = @import("events.zig");

const TileType = enum(u8) {
    Empty,
    Grass,
    Road,
};

const Tile = struct {
    type: TileType,
    color: rl.Color,
};

const Field = struct {
    width: i32,
    height: i32,
    tiles: std.ArrayList(Tile),
    size: f32,

    pub fn init(width: i32, height: i32, allocator: std.mem.Allocator) !Field {
        return Field{
            .width = width,
            .height = height,
            .tiles = std.ArrayList(Tile).init(allocator),
            .size = @floatFromInt(rl.getFontDefault().baseSize),
        };
    }

    pub fn deinit(self: *Field) void {
        self.tiles.deinit();
    }

    pub fn fillAll(self: *Field, tile: Tile) void {
        self.tiles.resize(@intCast(self.width * self.height)) catch unreachable;
        for (self.tiles.items) |*t| {
            t.* = tile;
        }
    }

    pub fn getTileMut(self: *Field, x: usize, y: usize) *Tile {
        std.debug.assert(x < self.width and y < self.height);
        return &self.tiles.items[x + y * @as(usize, @intCast(self.width))];
    }

    pub fn render(self: Field, posX: i32, posY: i32) void {
        const pos_x: f32 = @floatFromInt(posX);
        const pos_y: f32 = @floatFromInt(posY);
        for (self.tiles.items, 0..) |tile, idx| {
            const pos: i32 = @intCast(idx);
            const x: f32 = @floatFromInt(@mod(pos, self.width));
            const y: f32 = @floatFromInt(@divTrunc(pos, self.width));

            var value: [*:0]const u8 = undefined;
            switch (tile.type) {
                TileType.Empty => value = " ",
                TileType.Grass => value = "#",
                TileType.Road => value = "=",
            }
            rl.drawTextEx(rl.getFontDefault(), value, rl.Vector2{ .x = (pos_x + x) * self.size, .y = (pos_y + y) * self.size }, self.size, 0, tile.color);
        }
    }

    pub fn drawPlayer(self: Field, x: i32, y: i32) void {
        rl.drawTextEx(rl.getFontDefault(), "*", rl.Vector2{ .x = @as(f32, @floatFromInt(x)) * self.size, .y = @as(f32, @floatFromInt(y)) * self.size }, self.size, 0, rl.Color.brown);
    }
};

pub fn main() !void {
    rl.initWindow(800, 600, "Hi");
    defer rl.closeWindow();

    const canvasLayers = [_]rl.RenderTexture2D{ rl.loadRenderTexture(200, 150), rl.loadRenderTexture(200, 150) };
    defer for (canvasLayers) |layer| layer.unload();

    rl.setTextureFilter(canvasLayers[0].texture, rl.TextureFilter.point);

    var field = Field.init(10, 10, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    field.fillAll(Tile{ .type = TileType.Grass, .color = rl.Color.green });
    for (4..6) |y| {
        for (0..6) |x| {
            field.getTileMut(x, y).type = TileType.Road;
            field.getTileMut(x, y).color = rl.Color.yellow;
        }
    }
    for (0..4) |y| {
        for (4..6) |x| {
            field.getTileMut(x, y).type = TileType.Road;
            field.getTileMut(x, y).color = rl.Color.yellow;
        }
    }

    var pos: [2]i32 = .{ 0, 3 };

    rl.setTargetFPS(30);
    while (!rl.windowShouldClose()) {
        canvasLayers[0].begin();

        rl.clearBackground(rl.Color.white);
        if (rl.isKeyPressed(rl.KeyboardKey.d)) {
            pos[0] += 1;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.a)) {
            pos[0] -= 1;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.w)) {
            pos[1] -= 1;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.s)) {
            pos[1] += 1;
        }

        field.render(0, 0);
        canvasLayers[0].end();
        canvasLayers[1].begin();
        rl.clearBackground(rl.Color.fromInt(0));
        field.drawPlayer(pos[0], pos[1]);
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
