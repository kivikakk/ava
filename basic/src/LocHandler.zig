const PrintLoc = @This();

col: usize = 1,

pub fn write(self: *PrintLoc, m: []const u8) void {
    for (m) |c| {
        if (c == '\n') {
            self.col = 1;
        } else {
            self.col += 1;
            if (self.col == 81)
                self.col = 1;
        }
    }
}

const Comma = union(enum) {
    newline,
    spaces: usize,
};

pub fn comma(self: PrintLoc) Comma {
    // QBASIC splits the textmode screen up into 14 character "print zones".
    // Comma advances to the next, ensuring at least one space is included. i.e.
    // print zones start at column 1, 15, 29, 43, 57, 71. If you're at columns
    // 1-13 and print a comma, you'll wind up at column 15. Columns 14-27
    // advance to 29. (14 included because 14 advancing to 15 wouldn't leave a
    // space.) Why do arithmetic when just writing it out will do?
    // TODO: this won't hold up for wider screens :)
    return if (self.col < 14)
        .{ .spaces = 15 - self.col }
    else if (self.col < 28)
        .{ .spaces = 29 - self.col }
    else if (self.col < 42)
        .{ .spaces = 43 - self.col }
    else if (self.col < 56)
        .{ .spaces = 57 - self.col }
    else if (self.col < 70)
        .{ .spaces = 71 - self.col }
    else
        .newline;
}
