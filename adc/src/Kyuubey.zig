const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @import("./Font.zig");

const Kyuubey = @This();

renderer: SDL.Renderer,
font: Font,

screen: [80 * 25]u16 = [_]u16{0} ** (80 * 25),
mouse_x: u16 = 100,
mouse_y: u16 = 100,
cursor_on: bool = true,
cursor_x: u16 = 0,
cursor_y: u16 = 0,
cursor_inhibit: bool = false,

alt_held: bool = false,
menubar_focus: bool = false,
selected_menu: usize = 0,

pub fn init(renderer: SDL.Renderer) !Kyuubey {
    const font = try Font.fromData(renderer, @embedFile("cp437.vga"));
    var qb = Kyuubey{ .renderer = renderer, .font = font };
    qb.render();
    return qb;
}

pub fn deinit(self: *Kyuubey) void {
    self.font.deinit();
}

pub fn textRefresh(self: *Kyuubey) !void {
    try self.renderer.clear();

    for (0..25) |y|
        for (0..80) |x| {
            var pair = self.screen[y * 80 + x];
            if (self.mouse_x / 8 == x and self.mouse_y / 16 == y)
                pair = ((7 - (pair >> 12)) << 12) |
                    ((7 - ((pair >> 8) & 0xF)) << 8) |
                    (pair & 0xFF);
            try self.font.render(self.renderer, pair, x, y);
        };

    if (self.cursor_on and !self.cursor_inhibit) {
        const pair = self.screen[self.cursor_y * 80 + self.cursor_x];
        const fg = Font.CgaColors[(pair >> 8) & 0xF];
        try self.renderer.setColorRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xFF), @intCast(fg & 0xFF), 255);
        try self.renderer.fillRect(.{
            .x = @intCast(self.cursor_x * 8),
            .y = @intCast(self.cursor_y * 16 + 16 - 3),
            .width = 8,
            .height = 2,
        });
    }

    self.renderer.present();
}

pub fn keyDown(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    _ = mod;
    if ((sym == .left_alt or sym == .right_alt) and !self.alt_held) {
        self.alt_held = true;
        self.render();
        try self.textRefresh();
    }
}

pub fn keyUp(self: *Kyuubey, sym: SDL.Keycode) !void {
    if ((sym == .left_alt or sym == .right_alt) and self.alt_held) {
        self.alt_held = false;

        if (!self.menubar_focus) {
            self.cursor_inhibit = true;
            self.menubar_focus = true;
            self.selected_menu = 0;
        } else {
            self.cursor_inhibit = false;
            self.menubar_focus = false;
        }

        // menubar focus ...

        self.render();
        try self.textRefresh();
    }
}

pub fn keyPress(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
    _ = mod;

    if (self.menubar_focus) {
        switch (sym) {
            .left => self.selected_menu = if (self.selected_menu == 0) 8 else self.selected_menu - 1,
            .right => self.selected_menu = if (self.selected_menu == 8) 0 else self.selected_menu + 1,
            .escape => {
                self.cursor_inhibit = false;
                self.menubar_focus = false;
            },
            else => {},
        }

        self.render();
        try self.textRefresh();
        return;
    }
}

pub fn mouseClick(self: *Kyuubey, button: SDL.MouseButton) !void {
    _ = button;

    self.render();
    try self.textRefresh();
}

pub fn render(self: *Kyuubey) void {
    @memset(&self.screen, 0x1700);

    for (0..80) |x|
        self.screen[x] = 0x7000;

    var offset: usize = 2;
    inline for (&.{ "File", "Edit", "View", "Search", "Run", "Debug", "Calls", "Options", "Help" }, 0..) |option, i| {
        if (std.mem.eql(u8, option, "Help"))
            offset = 73;
        self.renderMenuOption(option, offset, i);
        offset += option.len + 2;
    }
}

fn renderMenuOption(self: *Kyuubey, title: []const u8, start: usize, index: usize) void {
    const back: u16 = if (self.menubar_focus and self.selected_menu == index) 0x0700 else 0x7000;

    self.screen[start + 0] = back;
    self.screen[start + 1] = back | @as(u16, if (self.alt_held or self.menubar_focus) 0x0f00 else 0x0000) | title[0];
    for (title[1..], 1..) |c, j|
        self.screen[start + 1 + j] = back | c;
    self.screen[start + 1 + title.len] = back;
}

// ---

const Editor = struct {
    allocator: Allocator,
    immediate: bool,

    doc_lines: std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)),

    top: usize,
    height: usize,

    cursor_x: usize,
    cursor_y: usize,
    scroll_x: usize,
    scroll_y: usize,
};

const ShiftTable = [_][2]SDL.Keycode{
    .{ SDL.Keycode.apostrophe, SDL.Keycode.quote },
    .{ .comma, .less },
    // {SDLK_MINUS, SDLK_UNDERSCORE},
    // {SDLK_PERIOD, SDLK_GREATER},
    // {SDLK_SLASH, SDLK_QUESTION},
    // {SDLK_0, SDLK_RIGHTPAREN},
    // {SDLK_1, SDLK_EXCLAIM},
    // {SDLK_2, SDLK_AT},
    // {SDLK_3, SDLK_HASH},
    // {SDLK_4, SDLK_DOLLAR},
    // {SDLK_5, SDLK_PERCENT},
    // {SDLK_6, SDLK_CARET},
    // {SDLK_7, SDLK_AMPERSAND},
    // {SDLK_8, SDLK_ASTERISK},
    // {SDLK_9, SDLK_LEFTPAREN},
    // {SDLK_SEMICOLON, SDLK_COLON},
    // {SDLK_LEFTBRACKET, '{'},
    // {SDLK_BACKSLASH, '|'},
    // {SDLK_RIGHTBRACKET, '}'},
    // {SDLK_BACKQUOTE, '~'},
    // {SDLK_EQUALS, SDLK_PLUS},
};
