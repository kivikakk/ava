const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @This();

allocator: Allocator,
char_width: usize,
char_height: usize,
chars: []const []const u16,

charset_prepared: bool = false,
charset: [256]SDL.Texture = undefined,

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

pub fn fromGlyphTxt(allocator: Allocator, data: []const u8) !Font {
    var char_width: usize = undefined;
    var char_height: usize = undefined;

    var chars = std.ArrayList([]const u16).init(allocator);
    defer chars.deinit();
    errdefer for (chars.items) |c| allocator.free(c);

    var parser_state: enum {
        init,
        ready_next,
        line,
        ended,
    } = .init;

    var char = std.ArrayList(u16).init(allocator);
    defer char.deinit();

    var it = std.mem.tokenizeScalar(u8, data, '\n');
    while (it.next()) |line| {
        switch (parser_state) {
            .init => {
                if (line.len == 0 or line[0] == '#') continue;
                var nit = std.mem.tokenizeScalar(u8, line, ',');
                char_width = try std.fmt.parseInt(usize, nit.next().?, 10);
                char_height = try std.fmt.parseInt(usize, nit.next().?, 10);
                if (nit.next() != null) return error.BadGlyph;
                parser_state = .ready_next;
            },
            .ready_next => {
                if (line.len == 0 or line[0] != '-') return error.BadGlyph;
                std.debug.assert(char.items.len == 0);
                if (chars.items.len == 256)
                    parser_state = .ended
                else
                    parser_state = .line;
            },
            .line => {
                if (line.len != char_width) return error.BadGlyph;
                var c: u16 = 0;
                for (0..char_width) |x|
                    if (line[char_width - 1 - x] != ' ') {
                        c |= @as(u16, 1) << @intCast(x);
                    };
                try char.append(c);
                if (char.items.len == char_height) {
                    try chars.append(try char.toOwnedSlice());
                    parser_state = .ready_next;
                }
            },
            .ended => return error.BadGlyph,
        }
    }

    if (parser_state != .ended) return error.BadGlyph;

    return .{
        .allocator = allocator,
        .char_width = char_width,
        .char_height = char_height,
        .chars = try chars.toOwnedSlice(),
    };
}

pub fn deinit(self: *Font) void {
    for (self.chars) |c|
        self.allocator.free(c);
    self.allocator.free(self.chars);

    if (self.charset_prepared)
        for (self.charset) |t|
            t.destroy();
}

pub fn prepare(self: *Font, renderer: SDL.Renderer) !void {
    var charset = [_]SDL.Texture{undefined} ** 256;

    for (0..256) |i| {
        var t = try SDL.createTexture(renderer, .rgba8888, .target, self.char_width, self.char_height);
        try t.setBlendMode(.blend);
        try renderer.setTarget(t);
        try renderer.setColorRGBA(0, 0, 0, 0);
        try renderer.clear();
        try renderer.setColorRGBA(255, 255, 255, 255);

        for (0..self.char_height) |row| {
            const rowdata = self.chars[i][row];
            var mask = @as(u16, 1) << @intCast(self.char_width - 1);
            for (0..self.char_width) |offset| {
                if (rowdata & mask != 0)
                    try renderer.drawPoint(@intCast(offset), @intCast(row));
                mask >>= 1;
            }
        }

        charset[i] = t;
    }

    try renderer.setTarget(null);

    self.charset_prepared = true;
    self.charset = charset;
}

pub fn render(self: *Font, renderer: SDL.Renderer, pair: u16, x: usize, y: usize) !void {
    std.debug.assert(self.charset_prepared);

    const bg = CgaColors[(pair >> (8 + 4)) & 0x7];
    const fg = CgaColors[(pair >> 8) & 0xf];
    const character: u8 = @intCast(pair & 0xff);

    try renderer.setColorRGBA(@intCast(bg >> 16), @intCast((bg >> 8) & 0xff), @intCast(bg & 0xff), 255);
    try renderer.fillRect(.{ .x = @intCast(x * self.char_width), .y = @intCast(y * self.char_height), .width = @intCast(self.char_width), .height = @intCast(self.char_height) });

    try self.charset[character].setColorModRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xff), @intCast(fg & 0xff), 255);
    try renderer.copy(
        self.charset[character],
        .{ .x = @intCast(x * self.char_width), .y = @intCast(y * self.char_height), .width = @intCast(self.char_width), .height = @intCast(self.char_height) },
        .{ .x = 0, .y = 0, .width = @intCast(self.char_width), .height = @intCast(self.char_height) },
    );
}
