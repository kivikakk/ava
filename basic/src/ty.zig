const std = @import("std");

pub const Type = enum {
    const Self = @This();

    integer,
    long,
    single,
    double,
    string,

    pub fn sigil(self: Self) u8 {
        return switch (self) {
            .integer => '%',
            .long => '&',
            .single => '!',
            .double => '#',
            .string => '$',
        };
    }

    pub fn fromSigil(s: u8) ?Self {
        return switch (s) {
            '%' => .integer,
            '&' => .long,
            '!' => .single,
            '#' => .double,
            '$' => .string,
            else => null,
        };
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        for (@tagName(self)) |c|
            try writer.writeByte(std.ascii.toUpper(c));
    }
};
