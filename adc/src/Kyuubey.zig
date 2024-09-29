const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Font = @import("./Font.zig");
const Editor = @import("./Editor.zig");

const Kyuubey = @This();

allocator: Allocator,
renderer: SDL.Renderer,
font: Font,

screen: [80 * 25]u16 = [_]u16{0} ** (80 * 25),
mouse_x: usize = 100,
mouse_y: usize = 100,
cursor_on: bool = true,
cursor_x: usize = 0,
cursor_y: usize = 0,
cursor_inhibit: bool = false,

alt_held: bool = false,
menubar_focus: bool = false,
selected_menu: usize = 0,

main_editor: Editor,
immediate_editor: Editor,

// TODO:
// * virtual space
//   * hold right. (then type!)
//   * can just scroll to the right.
//   * kind of always one more line down.

pub fn init(allocator: Allocator, renderer: SDL.Renderer) !Kyuubey {
    const font = try Font.fromData(renderer, @embedFile("cp437.vga"));
    var qb = Kyuubey{
        .allocator = allocator,
        .renderer = renderer,
        .font = font,
        .main_editor = try Editor.init(allocator, "Untitled", 1, 19, false),
        .immediate_editor = try Editor.init(allocator, "Immediate", 21, 2, true),
    };
    qb.render();
    return qb;
}

pub fn deinit(self: *Kyuubey) void {
    self.main_editor.deinit();
    self.immediate_editor.deinit();
    self.font.deinit();
}

pub fn textRefresh(self: *Kyuubey) !void {
    try self.renderer.clear();

    for (0..25) |y|
        for (0..80) |x| {
            var pair = self.screen[y * 80 + x];
            if (self.mouse_x / 8 == x and self.mouse_y / 16 == y)
                pair = ((7 - (pair >> 12)) << 12) |
                    ((7 - ((pair >> 8) & 0x7)) << 8) |
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

        self.render();
        try self.textRefresh();
    }
}

pub fn keyPress(self: *Kyuubey, sym: SDL.Keycode, mod: SDL.KeyModifierSet) !void {
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

    var editor = &self.main_editor;

    if (sym == .down and editor.cursor_y < editor.doc_lines.items.len - 1) {
        editor.cursor_y += 1;
        editor.cursor_x = @min(editor.cursor_x, editor.currentDocLine().items.len);
    } else if (sym == .up and editor.cursor_y > 0) {
        editor.cursor_y -= 1;
        editor.cursor_x = @min(editor.cursor_x, editor.currentDocLine().items.len);
    } else if (sym == .left and editor.cursor_x > 0) {
        editor.cursor_x -= 1;
    } else if (sym == .right) {
        if (editor.cursor_x < editor.currentDocLine().items.len)
            editor.cursor_x += 1;
    } else if (isPrintableKey(sym) and editor.currentDocLine().items.len < 255) {
        var doc_line = editor.currentDocLine();
        try doc_line.insert(editor.cursor_x, getCharacter(sym, mod));
        editor.cursor_x += 1;
    } else if (sym == .@"return") {
        var current_line = editor.currentDocLine();
        var next_line = std.ArrayList(u8).init(self.allocator);
        try next_line.appendSlice(current_line.items[editor.cursor_x..]);
        try current_line.replaceRange(editor.cursor_x, current_line.items.len - editor.cursor_x, &.{});
        try editor.doc_lines.insert(editor.cursor_y + 1, next_line);
        editor.cursor_x = 0;
        editor.cursor_y += 1;
    } else if (sym == .backspace) {
        try editor.deleteAt(.backspace);
    } else if (sym == .delete) {
        try editor.deleteAt(.delete);
    } else if (sym == .home) {
        editor.cursor_x = 0;
    } else if (sym == .end) {
        editor.cursor_x = @intCast(editor.currentDocLine().items.len);
    }

    if (editor.cursor_y < editor.scroll_y) {
        editor.scroll_y = editor.cursor_y;
    } else if (editor.cursor_y > editor.scroll_y + editor.height - 2) {
        editor.scroll_y = editor.cursor_y + 2 - editor.height;
    }

    if (editor.cursor_x < editor.scroll_x) {
        editor.scroll_x = editor.cursor_x;
    } else if (editor.cursor_x > editor.scroll_x + 77) {
        editor.scroll_x = editor.cursor_x - 77;
    }

    self.render();
    try self.textRefresh();
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

    const active_editor = &self.main_editor;
    self.renderEditor(&self.main_editor, active_editor == &self.main_editor);
    self.renderEditor(&self.immediate_editor, active_editor == &self.immediate_editor);

    for (0..80) |x|
        self.screen[24 * 80 + x] = 0x3000;

    offset = 1;
    inline for (&.{ "<Shift+F1=Help>", "<F6=Window>", "<F2=Subs>", "<F5=Run>", "<F8=Step>" }) |item| {
        self.renderHelpItem(item, offset);
        offset += item.len + 1;
    }

    self.screen[24 * 80 + 62] |= 0xb3;
    var buf: [9]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{d:0>5}:{d:0>3}", .{ active_editor.cursor_y + 1, active_editor.cursor_x + 1 }) catch unreachable;
    for (buf, 0..) |c, j|
        self.screen[24 * 80 + 70 + j] += c;

    self.cursor_x = active_editor.cursor_x + 1 - active_editor.scroll_x;
    self.cursor_y = active_editor.cursor_y + 1 - active_editor.scroll_y + active_editor.top;
}

fn renderMenuOption(self: *Kyuubey, title: []const u8, start: usize, index: usize) void {
    const back: u16 = if (self.menubar_focus and self.selected_menu == index) 0x0700 else 0x7000;

    self.screen[start + 0] = back;
    self.screen[start + 1] = back | @as(u16, if (self.alt_held or self.menubar_focus) 0x0f00 else 0x0000) | title[0];
    for (title[1..], 1..) |c, j|
        self.screen[start + 1 + j] = back | c;
    self.screen[start + 1 + title.len] = back;
}

fn renderHelpItem(self: *Kyuubey, item: []const u8, start: usize) void {
    for (item, 0..) |c, j|
        self.screen[24 * 80 + start + j] |= c;
}

fn renderEditor(self: *Kyuubey, editor: *Editor, active: bool) void {
    self.screen[editor.top * 80 + 0] = if (editor.top == 1) 0x17da else 0x17c3;
    for (1..79) |x|
        self.screen[editor.top * 80 + x] = 0x17c4;

    const start = 40 - editor.title.len / 2;
    const color: u16 = if (active) 0x7100 else 0x1700;
    self.screen[editor.top * 80 + start - 1] = color;
    for (editor.title, 0..) |c, j|
        self.screen[editor.top * 80 + start + j] = color | c;
    self.screen[editor.top * 80 + start + editor.title.len] = color;
    self.screen[editor.top * 80 + 79] = if (editor.top == 1) 0x17bf else 0x17b4;

    if (!editor.immediate) {
        self.screen[editor.top * 80 + 75] = 0x17b4;
        // If maximised: self.screen[editor.top * 80 + 76] = 0x7112;
        self.screen[editor.top * 80 + 76] = 0x7118;
        self.screen[editor.top * 80 + 77] = 0x17c3;
    }

    for (editor.top + 1..editor.top + 1 + editor.height) |y| {
        self.screen[y * 80 + 0] = 0x17b3;
        self.screen[y * 80 + 79] = 0x17b3;
        for (1..79) |x|
            self.screen[y * 80 + x] = 0x1700;
    }

    for (0..@min(editor.height, editor.doc_lines.items.len - editor.scroll_y)) |y| {
        const line = &editor.doc_lines.items[editor.scroll_y + y];
        const upper =
            @min(line.items.len, 78 + editor.scroll_x);
        if (upper > editor.scroll_x) {
            for (editor.scroll_x..upper) |x|
                self.screen[(y + editor.top + 1) * 80 + 1 + x - editor.scroll_x] |= line.items[x];
        }
    }

    if (active and !editor.immediate) {
        if (editor.height > 3) {
            self.screen[(editor.top + 1) * 80 + 79] = 0x7018;
            for (editor.top + 2..editor.top + editor.height - 1) |y|
                self.screen[y * 80 + 79] = 0x70b0;

            if (editor.doc_lines.items.len == 1)
                self.screen[(editor.top + 2) * 80 + 79] = 0x0000
            else
                self.screen[(editor.top + 2 + (editor.cursor_y * (editor.height - 4) / (editor.doc_lines.items.len - 1))) * 80 + 79] = 0x0000;

            self.screen[(editor.top + editor.height - 1) * 80 + 79] = 0x7019;
        }

        self.screen[(editor.top + editor.height) * 80 + 1] = 0x701b;
        for (2..78) |x|
            self.screen[(editor.top + editor.height) * 80 + x] = 0x70b0;
        self.screen[(editor.top + editor.height) * 80 + (editor.scroll_x * 75 / 178) + 2] = 0x0000;
        self.screen[(editor.top + editor.height) * 80 + 78] = 0x701a;
    }
}

// ---

fn isPrintableKey(sym: SDL.Keycode) bool {
    return @intFromEnum(sym) >= @intFromEnum(SDL.Keycode.space) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z);
}

fn getCharacter(sym: SDL.Keycode, mod: SDL.KeyModifierSet) u8 {
    if (@intFromEnum(sym) >= @intFromEnum(SDL.Keycode.a) and
        @intFromEnum(sym) <= @intFromEnum(SDL.Keycode.z))
    {
        if (mod.get(.left_shift) or mod.get(.right_shift) or mod.get(.caps_lock)) {
            return @as(u8, @intCast(@intFromEnum(sym))) - ('a' - 'A');
        }
        return @intCast(@intFromEnum(sym));
    }

    if (mod.get(.left_shift) or mod.get(.right_shift)) {
        for (ShiftTable) |e| {
            if (e.@"0" == sym)
                return e.@"1";
        }
    }

    return @intCast(@intFromEnum(sym));
}

const ShiftTable = [_]struct { SDL.Keycode, u8 }{
    .{ .apostrophe, '"' },
    .{ .comma, '<' },
    .{ .minus, '_' },
    .{ .period, '>' },
    .{ .slash, '?' },
    .{ .@"0", ')' },
    .{ .@"1", '!' },
    .{ .@"2", '@' },
    .{ .@"3", '#' },
    .{ .@"4", '$' },
    .{ .@"5", '%' },
    .{ .@"6", '^' },
    .{ .@"7", '&' },
    .{ .@"8", '*' },
    .{ .@"9", '(' },
    .{ .semicolon, ':' },
    .{ .left_bracket, '{' },
    .{ .backslash, '|' },
    .{ .right_bracket, '}' },
    .{ .grave, '~' },
    .{ .equals, '+' },
};
