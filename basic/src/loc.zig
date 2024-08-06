const std = @import("std");

pub const Loc = struct {
    const Self = @This();

    row: usize = 0,
    col: usize = 0,

    pub fn back(self: Loc) Loc {
        std.debug.assert(self.col > 1);
        return .{ .row = self.row, .col = self.col - 1 };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "({d}:{d})", .{ self.row, self.col });
    }
};

pub const Range = struct {
    const Self = @This();

    start: Loc = .{},
    end: Loc = .{},

    pub fn init(start: struct { usize, usize }, end: struct { usize, usize }) Self {
        return .{
            .start = .{ .row = start[0], .col = start[1] },
            .end = .{ .row = end[0], .col = end[1] },
        };
    }

    pub fn initEnds(r1: Range, r2: Range) Self {
        return .{ .start = r1.start, .end = r2.end };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{any}-{any}", .{ self.start, self.end });
    }
};

pub fn WithRange(comptime T: type) type {
    return struct {
        const Self = @This();

        payload: T,
        range: Range,

        pub fn init(t: T, range: Range) Self {
            return .{ .payload = t, .range = range };
        }
    };
}
