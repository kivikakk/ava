const std = @import("std");
const Allocator = std.mem.Allocator;

const Editor = @This();

allocator: Allocator,
title: []const u8,
immediate: bool,

doc_lines: std.ArrayList(std.ArrayList(u8)),

top: u16,
height: usize,

cursor_x: u16 = 0,
cursor_y: u16 = 0,
scroll_x: u16 = 0,
scroll_y: u16 = 0,

pub fn init(allocator: Allocator, title: []const u8, top: u16, height: usize, immediate: bool) !Editor {
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

pub fn deleteAt(self: *Editor, mode: enum { backspace, delete }) !void {
    const offset = self.cursor_x;

    if (mode == .backspace and offset == 0) {
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
    }
}
