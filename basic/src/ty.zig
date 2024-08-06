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

    pub fn widen(self: Self, rhs: Self) ?Self {
        return switch (self) {
            .integer => switch (rhs) {
                .integer => .integer,
                .long => .long,
                .single => .single,
                .double => .double,
                .string => null,
            },
            .long => switch (rhs) {
                .integer => .long,
                .long => .long,
                .single => .single,
                .double => .double,
                .string => null,
            },
            .single => switch (rhs) {
                .integer => .single,
                .long => .single,
                .single => .single,
                .double => .double,
                .string => null,
            },
            .double => switch (rhs) {
                .integer => .double,
                .long => .double,
                .single => .double,
                .double => .double,
                .string => null,
            },
            .string => switch (rhs) {
                .integer => null,
                .long => null,
                .single => null,
                .double => null,
                .string => .string,
            },
        };
    }
};
