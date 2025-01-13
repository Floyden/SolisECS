const std = @import("std");
const solis = @import("solis");
const rl = solis.raylib;

const TextureAtlas = @This();

pub const Index = enum(u32) {
    none = std.math.maxInt(u32),
    _,
};

width: i32,
height: i32,
columns: u32,
offset: i32,
image: rl.Image,
texture: rl.Texture2D,

pub fn init_from_path(width: i32, height: i32, path: [:0]const u8) TextureAtlas {
    const image = rl.loadImage(path);
    const texture = rl.loadTextureFromImage(image);
    const columns: u32 = @intCast(@divFloor(image.width, width));
    return TextureAtlas{ .width = width, .height = height, .columns = columns, .offset = 0, .image = image, .texture = texture };
}

pub fn deinit(self: TextureAtlas) void {
    rl.unloadTexture(self.texture);
    rl.unloadImage(self.image);
}

pub fn indexAt(self: TextureAtlas, x: u32, y: u32) Index {
    return @enumFromInt(x + y * self.columns);
}

pub fn indexPos(self: TextureAtlas, index: Index) [2]u32 {
    std.debug.assert(index != Index.none);
    const idx = @intFromEnum(index);
    return .{ @mod(idx, self.columns), @divTrunc(idx, self.columns) };
}

pub fn drawTile(self: TextureAtlas, index: Index, posX: f32, posY: f32) void {
    const location = self.indexPos(index);
    const column: f32 = @floatFromInt(location[0]);
    const row: f32 = @floatFromInt(location[1]);
    const width: f32 = @floatFromInt(self.width);
    const height: f32 = @floatFromInt(self.height);
    rl.drawTextureRec(
        self.texture,
        rl.Rectangle{ .x = column * width, .y = row * height, .width = width, .height = height },
        rl.Vector2{ .x = posX, .y = posY },
        rl.Color.white,
    );
}
