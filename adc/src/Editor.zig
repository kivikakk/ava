const std = @import("std");
const Allocator = std.mem.Allocator;

const Editor = @This();

allocator: Allocator,
title: []const u8,
immediate: bool,

lines: std.ArrayList(std.ArrayList(u8)),

top: usize,
height: usize,

cursor_x: usize = 0,
cursor_y: usize = 0,
scroll_x: usize = 0,
scroll_y: usize = 0,

pub fn init(allocator: Allocator, title: []const u8, top: usize, height: usize, immediate: bool) !Editor {
    return .{
        .allocator = allocator,
        .title = try allocator.dupe(u8, title),
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

pub fn splitLine(self: *Editor) !usize {
    var current = try self.currentLine();
    const first = lineFirst(current.items);
    var next = std.ArrayList(u8).init(self.allocator);
    try next.appendNTimes(' ', first);

    const appending = current.items[self.cursor_x..];
    try next.appendSlice(std.mem.trimLeft(u8, appending, " "));
    try current.replaceRange(self.cursor_x, current.items.len - self.cursor_x, &.{});
    try self.lines.insert(self.cursor_y + 1, next);
    return first;
}

pub fn deleteAt(self: *Editor, mode: enum { backspace, delete }) !void {
    if (mode == .backspace and self.cursor_x == 0) {
        if (self.cursor_y == 0) {
            //  WRONG  //
            //   WAY   //
            // GO BACK //
            return;
        }

        if (self.cursor_y == self.lines.items.len)
            self.cursor_y -= 1
        else {
            const removed = self.lines.orderedRemove(self.cursor_y);
            self.cursor_y -= 1;
            try (try self.currentLine()).appendSlice(removed.items);
            removed.deinit();
        }
        self.cursor_x = @intCast((try self.currentLine()).items.len);
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
