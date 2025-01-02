const std = @import("std");
const rl = @import("raylib");

const TileType = enum(u8) {
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
    pub fn init(width: i32, height: i32, allocator: std.mem.Allocator) !Field {
        return Field{
            .width = width,
            .height = height,
            .tiles = std.ArrayList(Tile).init(allocator),
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
        return self.tiles.items[x + y * self.width];
    }

    pub fn render(self: Field, posX: i32, posY: i32) void {
        const size: i32 = 20;
        for (self.tiles.items, 0..) |tile, idx| {
            const pos: i32 = @intCast(idx);
            const x: i32 = @mod(pos, self.width) * 10;
            const y: i32 = @divTrunc(pos, self.width) * 15;

            switch (tile.type) {
                TileType.Grass => rl.drawText("V", posX + x, posY + y, size, tile.color),
                TileType.Road => rl.drawText("=", posX + x, posY + y, size, tile.color),
            }
        }
    }
};

pub fn main() !void {
    rl.initWindow(800, 600, "Hi");
    defer rl.closeWindow();

    var field = Field.init(100, 100, std.heap.page_allocator) catch unreachable;
    defer field.deinit();

    field.fillAll(Tile{ .type = TileType.Grass, .color = rl.Color.green });

    rl.setTargetFPS(60);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.white);

        field.render(0, 0);
    }
}
