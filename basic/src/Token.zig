const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const loc = @import("loc.zig");
const Range = loc.Range;
const Tokenizer = @import("Tokenizer.zig");

const Token = @This();

payload: Payload,
range: Range,

pub fn init(payload: Payload, range: Range) Token {
    return .{ .payload = payload, .range = range };
}

pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try std.fmt.format(writer, "{any} {any}", .{ self.range, self.payload });
}

// Any references belong to the input string.
pub const Payload = union(enum) {
    const Self = @This();

    number: i64,
    label: []const u8,
    remark: []const u8, // includes leading "REM " or "'"
    string: []const u8, // doesn't include surrounding quotes
    jumplabel: []const u8, // includes trailing ":"
    fileno: usize, // XXX: doesn't support variable
    linefeed,
    comma,
    semicolon,
    colon,
    equals,
    plus,
    minus,
    asterisk,
    fslash,
    pareno,
    parenc,
    angleo,
    anglec,
    diamond,
    lte,
    gte,
    kw_if,
    kw_then,
    kw_elseif,
    kw_else,
    kw_end,
    kw_goto,
    kw_for,
    kw_to,
    kw_step,
    kw_next,
    kw_dim,
    kw_as,
    kw_gosub,
    kw_return,
    kw_stop,
    kw_do,
    kw_loop,
    kw_while,
    kw_until,
    kw_wend,
    kw_let,
    kw_and,
    kw_or,
    kw_xor,

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .number => |n| try std.fmt.format(writer, "Number({d})", .{n}),
            .label => |l| try std.fmt.format(writer, "Label({s})", .{l}),
            .remark => |r| try std.fmt.format(writer, "Remark({s})", .{r}),
            .string => |s| try std.fmt.format(writer, "String({s})", .{s}),
            .jumplabel => |jl| try std.fmt.format(writer, "Jumplabel({s})", .{jl}),
            .fileno => |n| try std.fmt.format(writer, "Fileno({d})", .{n}),
            .linefeed => try std.fmt.format(writer, "Linefeed", .{}),
            .comma => try std.fmt.format(writer, "Comma", .{}),
            .semicolon => try std.fmt.format(writer, "Semicolon", .{}),
            .colon => try std.fmt.format(writer, "Colon", .{}),
            .equals => try std.fmt.format(writer, "Equals", .{}),
            .plus => try std.fmt.format(writer, "Plus", .{}),
            .minus => try std.fmt.format(writer, "Minus", .{}),
            .asterisk => try std.fmt.format(writer, "Asterisk", .{}),
            .fslash => try std.fmt.format(writer, "Fslash", .{}),
            .pareno => try std.fmt.format(writer, "Pareno", .{}),
            .parenc => try std.fmt.format(writer, "Parenc", .{}),
            .angleo => try std.fmt.format(writer, "Angleo", .{}),
            .anglec => try std.fmt.format(writer, "Anglec", .{}),
            .diamond => try std.fmt.format(writer, "Diamond", .{}),
            .lte => try std.fmt.format(writer, "Lte", .{}),
            .gte => try std.fmt.format(writer, "Gte", .{}),
            .kw_if => try std.fmt.format(writer, "IF", .{}),
            .kw_then => try std.fmt.format(writer, "THEN", .{}),
            .kw_elseif => try std.fmt.format(writer, "ELSEIF", .{}),
            .kw_else => try std.fmt.format(writer, "ELSE", .{}),
            .kw_end => try std.fmt.format(writer, "END", .{}),
            .kw_goto => try std.fmt.format(writer, "GOTO", .{}),
            .kw_for => try std.fmt.format(writer, "FOR", .{}),
            .kw_to => try std.fmt.format(writer, "TO", .{}),
            .kw_step => try std.fmt.format(writer, "STEP", .{}),
            .kw_next => try std.fmt.format(writer, "NEXT", .{}),
            .kw_dim => try std.fmt.format(writer, "DIM", .{}),
            .kw_as => try std.fmt.format(writer, "AS", .{}),
            .kw_gosub => try std.fmt.format(writer, "GOSUB", .{}),
            .kw_return => try std.fmt.format(writer, "RETURN", .{}),
            .kw_stop => try std.fmt.format(writer, "STOP", .{}),
            .kw_do => try std.fmt.format(writer, "DO", .{}),
            .kw_loop => try std.fmt.format(writer, "LOOP", .{}),
            .kw_while => try std.fmt.format(writer, "WHILE", .{}),
            .kw_until => try std.fmt.format(writer, "UNTIL", .{}),
            .kw_wend => try std.fmt.format(writer, "WEND", .{}),
            .kw_let => try std.fmt.format(writer, "LET", .{}),
            .kw_and => try std.fmt.format(writer, "AND", .{}),
            .kw_or => try std.fmt.format(writer, "OR", .{}),
            .kw_xor => try std.fmt.format(writer, "XOR", .{}),
        }
    }
};

pub const Tag = std.meta.Tag(Payload);

test "formatting" {
    const tx = try Tokenizer.tokenize(testing.allocator,
        \\'Hello!!!!
    , null);
    defer testing.allocator.free(tx);

    try testing.expectFmt("<1:1-1:10> Remark('Hello!!!!)", "{any}", .{tx[0]});
}
