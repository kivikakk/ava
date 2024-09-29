const std = @import("std");
const SDL = @import("sdl2");

const Font = @This();

charset: [256]SDL.Texture,

pub const CgaColors = [16]u24{
    0x000000,
    0x0000AA,
    0x00AA00,
    0x00AAAA,
    0xAA0000,
    0xAA00AA,
    0xAA5500,
    0xAAAAAA,
    0x555555,
    0x5555FF,
    0x55FF55,
    0x55FFFF,
    0xFF5555,
    0xFF55FF,
    0xFFFF55,
    0xFFFFFF,
};

pub fn fromData(renderer: SDL.Renderer, data: []const u8) !Font {
    var charset = [_]SDL.Texture{undefined} ** 256;

    for (0..256) |i| {
        var t = try SDL.createTexture(renderer, .rgba8888, .target, 8, 16);
        try t.setBlendMode(.blend);
        try renderer.setTarget(t);
        try renderer.setColorRGBA(0, 0, 0, 0);
        try renderer.clear();
        try renderer.setColorRGBA(255, 255, 255, 255);

        for (0..16) |row| {
            const rowdata = data[i * 16 + row];
            var mask: u8 = 0x80;
            for (0..8) |offset| {
                if (rowdata & mask != 0)
                    try renderer.drawPoint(@intCast(offset), @intCast(row));
                mask >>= 1;
            }
        }

        charset[i] = t;
    }

    try renderer.setTarget(null);

    return .{ .charset = charset };
}

pub fn deinit(self: *Font) void {
    for (self.charset) |t|
        t.destroy();
}

pub fn render(self: *Font, renderer: SDL.Renderer, pair: u16, x: usize, y: usize) !void {
    const bg = CgaColors[(pair >> (8 + 4)) & 0x7];
    const fg = CgaColors[(pair >> 8) & 0xf];
    const character: u8 = @intCast(pair & 0xff);

    try renderer.setColorRGBA(@intCast(bg >> 16), @intCast((bg >> 8) & 0xff), @intCast(bg & 0xff), 255);
    try renderer.fillRect(.{ .x = @intCast(x * 8), .y = @intCast(y * 16), .width = 8, .height = 16 });

    // original didn't include alpha
    try self.charset[character].setColorModRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xff), @intCast(fg & 0xff), 255);
    try renderer.copy(
        self.charset[character],
        .{ .x = @intCast(x * 8), .y = @intCast(y * 16), .width = 8, .height = 16 },
        .{ .x = 0, .y = 0, .width = 8, .height = 16 },
    );
}
