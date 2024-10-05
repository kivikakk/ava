const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Editor = @This();

pub const Kind = enum {
    primary,
    secondary,
    immediate,
};

allocator: Allocator,
title: []const u8,
kind: Kind,

lines: std.ArrayList(std.ArrayList(u8)),

top: usize,
height: usize,
fullscreened: ?struct {
    old_top: usize,
    old_height: usize,
} = null,

cursor_x: usize = 0,
cursor_y: usize = 0,
scroll_x: usize = 0,
scroll_y: usize = 0,

pub const MAX_LINE = 255;

pub fn init(allocator: Allocator, title: []const u8, top: usize, height: usize, kind: Kind) !Editor {
    return .{
        .allocator = allocator,
        .title = try allocator.dupe(u8, title),
        .kind = kind,
        .lines = std.ArrayList(std.ArrayList(u8)).init(allocator),
        .top = top,
        .height = height,
    };
}

pub fn deinit(self: *Editor) void {
    self.allocator.free(self.title);
    for (self.lines.items) |line|
        line.deinit();
    self.lines.deinit();
}

pub fn load(self: *Editor, filename: []const u8) !void {
    self.deinit();
    self.lines = std.ArrayList(std.ArrayList(u8)).init(self.allocator);

    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();

    while (try f.reader().readUntilDelimiterOrEofAlloc(self.allocator, '\n', 10240)) |line|
        try self.lines.append(std.ArrayList(u8).fromOwnedSlice(self.allocator, line));

    const index = std.mem.lastIndexOfScalar(u8, filename, '/');
    self.title = try std.ascii.allocUpperString(
        self.allocator,
        if (index) |ix| filename[ix + 1 ..] else filename,
    );
}

pub fn loadFrom(self: *Editor, other: *const Editor) !void {
    self.deinit();
    self.lines = std.ArrayList(std.ArrayList(u8)).init(self.allocator);

    for (other.lines.items) |*ol|
        try self.lines.append(std.ArrayList(u8).fromOwnedSlice(
            self.allocator,
            try self.allocator.dupe(u8, ol.items),
        ));

    self.title = try self.allocator.dupe(u8, other.title);
}

pub fn currentLine(self: *Editor) !*std.ArrayList(u8) {
    if (self.cursor_y == self.lines.items.len)
        try self.lines.append(std.ArrayList(u8).init(self.allocator));
    return &self.lines.items[self.cursor_y];
}

pub fn maybeCurrentLine(self: *Editor) ?*std.ArrayList(u8) {
    if (self.cursor_y == self.lines.items.len)
        return null;
    return &self.lines.items[self.cursor_y];
}

pub fn lineFirst(line: []const u8) usize {
    for (line, 0..) |c, i|
        if (c != ' ')
            return i;
    return 0;
}

pub fn splitLine(self: *Editor) !void {
    var current = try self.currentLine();
    const first = lineFirst(current.items);
    var next = std.ArrayList(u8).init(self.allocator);
    try next.appendNTimes(' ', first);

    const appending = if (self.cursor_x < current.items.len) current.items[self.cursor_x..] else "";
    try next.appendSlice(std.mem.trimLeft(u8, appending, " "));
    try current.replaceRange(self.cursor_x, current.items.len - self.cursor_x, &.{});
    try self.lines.insert(self.cursor_y + 1, next);

    self.cursor_x = first;
    self.cursor_y += 1;
}

pub fn deleteAt(self: *Editor, mode: enum { backspace, delete }) !void {
    if (mode == .backspace and self.cursor_x == 0) {
        if (self.cursor_y == 0) {
            //  WRONG  //
            //   WAY   //
            // GO BACK //
            return;
        }

        if (self.cursor_y == self.lines.items.len) {
            self.cursor_y -= 1;
            self.cursor_x = @intCast((try self.currentLine()).items.len);
        } else {
            const removed = self.lines.orderedRemove(self.cursor_y);
            self.cursor_y -= 1;
            self.cursor_x = @intCast((try self.currentLine()).items.len);
            try (try self.currentLine()).appendSlice(removed.items);
            removed.deinit();
        }
    } else if (mode == .backspace) {
        // self.cursor_x > 0
        const line = try self.currentLine();
        const first = lineFirst(line.items);
        if (self.cursor_x == first) {
            var back_to: usize = 0;
            if (self.cursor_y > 0) {
                var y: usize = self.cursor_y - 1;
                while (true) : (y -= 1) {
                    const lf = lineFirst(self.lines.items[y].items);
                    if (lf < first) {
                        back_to = lf;
                        break;
                    }
                    if (y == 0) break;
                }
            }
            try line.replaceRange(0, first - back_to, &.{});
            self.cursor_x = back_to;
        } else {
            if (self.cursor_x - 1 < line.items.len)
                _ = line.orderedRemove(self.cursor_x - 1);
            self.cursor_x -= 1;
        }
    } else if (self.cursor_x == (try self.currentLine()).items.len) {
        // mode == .delete
        if (self.cursor_y == self.lines.items.len - 1)
            return;

        const removed = self.lines.orderedRemove(self.cursor_y + 1);
        try (try self.currentLine()).appendSlice(removed.items);
        removed.deinit();
    } else {
        // mode == .delete, self.cursor_x < self.currentLine().items.len
        _ = (try self.currentLine()).orderedRemove(self.cursor_x);
    }
}

pub fn toggleFullscreen(self: *Editor) void {
    if (self.fullscreened) |pre| {
        self.top = pre.old_top;
        self.height = pre.old_height;
        self.fullscreened = null;
    } else {
        self.fullscreened = .{
            .old_top = self.top,
            .old_height = self.height,
        };
        self.top = 1;
        self.height = 22;
    }
}

pub fn handleMouseDown(self: *Editor, active: bool, button: SDL.MouseButton, clicks: u8, x: usize, y: usize) bool {
    _ = button;
    _ = clicks;

    if (y == self.top)
        return true;

    if (y > self.top and y <= self.top + self.height and x > 0 and x < 79) {
        const scrollbar = self.kind != .immediate and y == self.top + self.height;
        if (scrollbar and active) {
            if (x == 1) {
                if (self.scroll_x > 0) {
                    self.scroll_x -= 1;
                    self.cursor_x -= 1;
                }
            } else if (x > 1 and x < 78) {
                const hst = self.horizontalScrollThumb();
                if (x - 2 < hst)
                    self.scroll_x = if (self.scroll_x >= 78) self.scroll_x - 78 else 0
                else if (x - 2 > hst)
                    self.scroll_x = if (self.scroll_x <= MAX_LINE - 77 - 78) self.scroll_x + 78 else MAX_LINE - 77
                else
                    self.scroll_x = (hst * (MAX_LINE - 77) + 74) / 75;
                self.cursor_x = self.scroll_x;
            } else if (x == 78) {
                if (self.scroll_x < (MAX_LINE - 77)) {
                    self.scroll_x += 1;
                    self.cursor_x += 1;
                }
            }
            if (self.cursor_x < self.scroll_x)
                self.cursor_x = self.scroll_x
            else if (self.cursor_x > self.scroll_x + 77)
                self.cursor_x = self.scroll_x + 77;
        } else {
            const eff_y = if (scrollbar) y - 1 else y;
            self.cursor_x = self.scroll_x + x - 1;
            self.cursor_y = @min(self.scroll_y + eff_y - self.top - 1, self.lines.items.len);
        }
        return true;
    }

    if (active and self.kind != .immediate and y > self.top and y < self.top + self.height and x == 79) {
        if (y == self.top + 1) {
            std.debug.print("^\n", .{});
        } else if (y > self.top + 1 and y < self.top + self.height - 1) {
            // TODO: Vertical scrollbar behaviour has a knack to it I don't
            // quite understand yet.  The horizontal scrollbar strictly relates
            // to the actual scroll of the window (scroll_x) --- it has nothing
            // to do with the cursor position itself (cursor_x) --- so it's
            // easy and predictable.
            //     The vertical scrollbar is totally different --- it shows the
            // cursor's position in the (virtual) document.  Thus, when using the
            // pgup/pgdn feature of it, we don't expect the thumb to go all
            // the way to the top or bottom most of the time, since that'd only
            // happen if cursor_y happened to land on 0 or self.lines.items.len.
            //
            // Let's make some observations:
            //
            // Scrolled to the very top, cursor on line 1. 1-18 are visible. (19
            //     under HSB.)
            // Clicking pgdn.
            // Now 19-36 are visible, cursor on 19.
            //
            // Scrolled to very top, cursor on line 3. 1-18 visible.
            // pgdn
            // 19-36 visible, cursor now on line 21. (not moved.)
            //
            // Actual pgup/pgdn seem to do the exact same thing.
            const vst = self.verticalScrollThumb();
            if (y - self.top - 2 < vst)
                self.pageUp()
            else if (y - self.top - 2 > vst)
                self.pageDown()
            else {
                // TODO: the thing, zhu li
            }
        } else if (y == self.top + self.height - 1) {
            std.debug.print("v\n", .{});
        }
        return true;
    }

    return false;
}

pub fn handleMouseUp(self: *Editor, button: SDL.MouseButton, clicks: u8, x: usize, y: usize) void {
    _ = button;

    if (y == self.top) {
        if ((self.kind != .immediate and x == 76) or clicks == 2)
            self.toggleFullscreen();
        return;
    }
}

pub fn pageUp(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    // std.debug.print("pgup\n", .{})
}

pub fn pageDown(self: *Editor) void {
    _ = self;
    // self.scroll_y = if (self.scroll_y >=
    // std.debug.print("pgup\n", .{})
}

pub fn horizontalScrollThumb(self: *const Editor) usize {
    return self.scroll_x * 75 / (MAX_LINE - 77);
}

pub fn verticalScrollThumb(self: *const Editor) usize {
    if (self.lines.items.len == 0)
        return 0;
    return self.cursor_y * (self.height - 4) / self.lines.items.len;
}
