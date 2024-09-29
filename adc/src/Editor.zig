const std = @import("std");
const Allocator = std.mem.Allocator;
const SDL = @import("sdl2");

const Editor = @This();

allocator: Allocator,
title: []const u8,
active: bool,
immediate: bool,

lines: std.ArrayList(std.ArrayList(u8)),

top: usize,
height: usize,

cursor_x: usize = 0,
cursor_y: usize = 0,
scroll_x: usize = 0,
scroll_y: usize = 0,

pub fn init(allocator: Allocator, title: []const u8, top: usize, height: usize, active: bool, immediate: bool) !Editor {
    return .{
        .allocator = allocator,
        .title = try allocator.dupe(u8, title),
        .active = active,
        .immediate = immediate,
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

pub fn maybeHandleClick(self: *Editor, button: SDL.MouseButton, x: usize, y: usize) bool {
    _ = button;

    if (y == self.top) {
        // TODO: full-screen control on non-imm windows (also double-click
        // on header -- this works on immediate too).
        self.active = true;
        return true;
    }

    if (y > self.top and y <= self.top + self.height and x > 0 and x < 79) {
        const scrollbar = !self.immediate and y == self.top + self.height;
        if (scrollbar and self.active) {
            if (x == 1) {
                if (self.scroll_x > 0) {
                    self.scroll_x -= 1;
                    self.cursor_x -= 1;
                }
            } else if (x > 1 and x < 78) {
                const hst = self.horizontalScrollThumb();
                if (x - 2 < hst) {
                    self.scroll_x = if (self.scroll_x >= 78) self.scroll_x - 78 else 0;
                } else if (x - 2 > hst) {
                    self.scroll_x = if (self.scroll_x <= 100) self.scroll_x + 78 else 178;
                } else {
                    self.scroll_x = (hst * 178 + 74) / 75;
                }
                self.cursor_x = self.scroll_x;
            } else if (x == 78) {
                if (self.scroll_x < 178) {
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
            self.active = true;
        }
        return true;
    }
    return false;
}

pub fn horizontalScrollThumb(self: *const Editor) usize {
    return self.scroll_x * 75 / 178;
}

pub fn verticalScrollThumb(self: *const Editor) usize {
    if (self.lines.items.len == 0)
        return 0;
    return self.cursor_y * (self.height - 4) / self.lines.items.len;
}
