const std = @import("std");
const Allocator = std.mem.Allocator;

const Editor = @This();

allocator: Allocator,
title: []const u8,
immediate: bool,

doc_lines: std.ArrayList(std.ArrayList(u8)),

top: usize,
height: usize,

cursor_x: usize = 0,
cursor_y: usize = 0,
scroll_x: usize = 0,
scroll_y: usize = 0,

pub fn init(allocator: Allocator, title: []const u8, top: usize, height: usize, immediate: bool) !Editor {
    var doc_lines = std.ArrayList(std.ArrayList(u8)).init(allocator);
    try doc_lines.append(std.ArrayList(u8).init(allocator));
    return .{
        .allocator = allocator,
        .title = try allocator.dupe(u8, title),
        .immediate = immediate,
        .doc_lines = doc_lines,
        .top = top,
        .height = height,
    };
}

pub fn deinit(self: *Editor) void {
    self.allocator.free(self.title);
    for (self.doc_lines.items) |line|
        line.deinit();
    self.doc_lines.deinit();
}

pub fn currentDocLine(self: *Editor) *std.ArrayList(u8) {
    return &self.doc_lines.items[self.cursor_y];
}

pub fn currentDocLineFirst(self: *Editor) usize {
    for (self.currentDocLine().items, 0..) |c, i|
        if (c != ' ')
            return i;
    return 0;
}

pub fn splitLine(self: *Editor) !void {
    var current_line = self.currentDocLine();
    var next_line = std.ArrayList(u8).init(self.allocator);
    try next_line.appendSlice(current_line.items[self.cursor_x..]);
    try current_line.replaceRange(self.cursor_x, current_line.items.len - self.cursor_x, &.{});
    try self.doc_lines.insert(self.cursor_y + 1, next_line);
}

pub fn deleteAt(self: *Editor, mode: enum { backspace, delete }) !void {
    if (mode == .backspace and self.cursor_x == 0) {
        if (self.cursor_y == 0) {
            //  WRONG  //
            //   WAY   //
            // GO BACK //
            return;
        }

        const removed = self.doc_lines.orderedRemove(self.cursor_y);
        self.cursor_y -= 1;
        self.cursor_x = @intCast(self.currentDocLine().items.len);
        try self.currentDocLine().appendSlice(removed.items);
        removed.deinit();
    } else if (mode == .backspace and self.cursor_x == self.currentDocLineFirst()) {
        // self.cursor_x > 0
        const f = self.currentDocLineFirst();
        try self.currentDocLine().replaceRange(0, f, &.{});
        self.cursor_x = 0;
    } else if (mode == .backspace) {
        // self.cursor_x > 0, self.cursor_x != self.currentDocLineFirst()
        _ = self.currentDocLine().orderedRemove(self.cursor_x - 1);
        self.cursor_x -= 1;
    } else if (self.cursor_x == self.currentDocLine().items.len) {
        // mode == .delete
        if (self.cursor_y == self.doc_lines.items.len - 1)
            return;

        const removed = self.doc_lines.orderedRemove(self.cursor_y + 1);
        try self.currentDocLine().appendSlice(removed.items);
        removed.deinit();
    } else {
        // mode == .delete, self.cursor_x < self.currentDocLine().items.len
        _ = self.currentDocLine().orderedRemove(self.cursor_x);
    }
}
