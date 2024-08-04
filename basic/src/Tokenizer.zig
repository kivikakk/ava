const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Token = @import("Token.zig");
const loc = @import("loc.zig");
const Loc = loc.Loc;
const Range = loc.Range;
const ErrorInfo = @import("ErrorInfo.zig");

const Tokenizer = @This();

loc: Loc = .{ .row = 1, .col = 1 },

pub const Error = error{
    UnexpectedChar,
    UnexpectedEnd,
};

const LocOffset = struct {
    loc: Loc,
    offset: usize,
};

const State = union(enum) {
    init,
    integer: LocOffset,
    floating: LocOffset,
    bareword: LocOffset,
    string: LocOffset,
    fileno: LocOffset,
    remark: LocOffset,
    angleo,
    anglec,
};

pub fn tokenize(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) ![]Token {
    var t = Tokenizer{};
    return t.feed(allocator, inp) catch |err| {
        if (errorinfo) |ei|
            ei.loc = t.loc;
        return err;
    };
}

fn feed(self: *Tokenizer, allocator: Allocator, inp: []const u8) ![]Token {
    var tx = std.ArrayList(Token).init(allocator);
    errdefer tx.deinit();

    var state: State = .init;
    var i: usize = 0;
    var rewind = false;
    while (i < inp.len) : ({
        if (rewind) {
            rewind = false;
        } else {
            if (inp[i] == '\n') {
                self.loc.row += 1;
                self.loc.col = 1;
            } else if (inp[i] == '\t') {
                self.loc.col += 1;
                while (self.loc.col % 8 != 0)
                    self.loc.col += 1;
            } else {
                self.loc.col += 1;
            }
            i += 1;
        }
    }) {
        const c = inp[i];

        switch (state) {
            .init => {
                if (c >= '0' and c <= '9') {
                    state = .{ .integer = .{ .loc = self.loc, .offset = i } };
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    state = .{ .bareword = .{ .loc = self.loc, .offset = i } };
                } else if (c == '"') {
                    state = .{ .string = .{ .loc = self.loc, .offset = i + 1 } };
                } else if (c == ' ') {
                    // nop
                } else if (c == '\t') {
                    // nop
                } else if (c == '\n') {
                    try tx.append(attach(.linefeed, self.loc, self.loc));
                } else if (c == '\'') {
                    state = .{ .remark = .{ .loc = self.loc, .offset = i } };
                } else if (c == ',') {
                    try tx.append(attach(.comma, self.loc, self.loc));
                } else if (c == ';') {
                    try tx.append(attach(.semicolon, self.loc, self.loc));
                } else if (c == ':') {
                    try tx.append(attach(.colon, self.loc, self.loc));
                } else if (c == '=') {
                    try tx.append(attach(.equals, self.loc, self.loc));
                } else if (c == '+') {
                    try tx.append(attach(.plus, self.loc, self.loc));
                } else if (c == '-') {
                    try tx.append(attach(.minus, self.loc, self.loc));
                } else if (c == '*') {
                    try tx.append(attach(.asterisk, self.loc, self.loc));
                } else if (c == '/') {
                    try tx.append(attach(.fslash, self.loc, self.loc));
                } else if (c == '(') {
                    try tx.append(attach(.pareno, self.loc, self.loc));
                } else if (c == ')') {
                    try tx.append(attach(.parenc, self.loc, self.loc));
                } else if (c == '<') {
                    state = .angleo;
                } else if (c == '>') {
                    state = .anglec;
                } else if (c == '#') {
                    state = .{ .fileno = .{ .loc = self.loc, .offset = i } };
                } else {
                    return Error.UnexpectedChar;
                }
            },
            .integer => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // XXX: 1e2 / 1d2 ?
                    return Error.UnexpectedChar;
                } else if (c == '.') {
                    state = .{ .floating = start };
                } else if (c == '!') {
                    try tx.append(attach(.{
                        .single = try std.fmt.parseFloat(f32, inp[start.offset..i]),
                    }, start.loc, self.loc));
                    state = .init;
                } else if (c == '#') {
                    try tx.append(attach(.{
                        .double = try std.fmt.parseFloat(f64, inp[start.offset..i]),
                    }, start.loc, self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(
                        try resolveIntegral(inp[start.offset..i]),
                        start.loc,
                        self.loc.back(),
                    ));
                    state = .init;
                    rewind = true;
                }
            },
            .floating => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // XXX: 1.0e2 / 1.0d2
                    return Error.UnexpectedChar;
                } else if (c == '!') {
                    try tx.append(attach(.{
                        .single = try std.fmt.parseFloat(f32, inp[start.offset..i]),
                    }, start.loc, self.loc));
                    state = .init;
                } else if (c == '#') {
                    try tx.append(attach(.{
                        .double = try std.fmt.parseFloat(f64, inp[start.offset..i]),
                    }, start.loc, self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(
                        try resolveFloating(inp[start.offset..i]),
                        start.loc,
                        self.loc.back(),
                    ));
                    state = .init;
                    rewind = true;
                }
            },
            .bareword => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // nop
                } else if (c == '%' or c == '&' or c == '!' or c == '#' or c == '$') {
                    try tx.append(attach(.{ .label = inp[start.offset .. i + 1] }, start.loc, self.loc));
                    state = .init;
                } else if (c == ':') {
                    try tx.append(attach(.{ .jumplabel = inp[start.offset .. i + 1] }, start.loc, self.loc));
                    state = .init;
                } else if (std.ascii.eqlIgnoreCase(inp[start.offset..i], "rem")) {
                    state = .{ .remark = start };
                } else {
                    try tx.append(attach(classifyBareword(inp[start.offset..i]), start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .string => |start| {
                if (c == '"') {
                    try tx.append(attach(.{ .string = inp[start.offset..i] }, start.loc, self.loc));
                    state = .init;
                } else {
                    // nop
                }
            },
            .fileno => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else {
                    try tx.append(attach(.{
                        .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 .. i], 10),
                    }, start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .remark => |start| {
                if (c == '\n') {
                    try tx.append(attach(.{
                        .remark = inp[start.offset..i],
                    }, start.loc, self.loc.back()));
                    state = .init;
                    rewind = true;
                } else {
                    // nop
                }
            },
            .angleo => {
                if (c == '>') { // <>
                    try tx.append(attach(.diamond, self.loc.back(), self.loc));
                    state = .init;
                } else if (c == '=') { // <=
                    try tx.append(attach(.lte, self.loc.back(), self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(.angleo, self.loc.back(), self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
            .anglec => {
                if (c == '=') { // >=
                    try tx.append(attach(.gte, self.loc.back(), self.loc));
                    state = .init;
                } else {
                    try tx.append(attach(.anglec, self.loc.back(), self.loc.back()));
                    state = .init;
                    rewind = true;
                }
            },
        }
    }

    switch (state) {
        .init => {},
        .integer => |start| try tx.append(attach(
            try resolveIntegral(inp[start.offset..]),
            start.loc,
            self.loc.back(),
        )),
        .floating => |start| try tx.append(attach(
            try resolveFloating(inp[start.offset..]),
            start.loc,
            self.loc.back(),
        )),
        .bareword => |start| {
            if (std.ascii.eqlIgnoreCase(inp[start.offset..], "rem")) {
                try tx.append(attach(.{
                    .remark = inp[start.offset..],
                }, start.loc, self.loc.back()));
            } else {
                try tx.append(attach(classifyBareword(inp[start.offset..]), start.loc, self.loc.back()));
            }
        },
        .string => return Error.UnexpectedEnd,
        .fileno => |start| try tx.append(attach(.{
            .fileno = try std.fmt.parseInt(usize, inp[start.offset + 1 ..], 10),
        }, start.loc, self.loc.back())),
        .remark => |start| try tx.append(attach(.{
            .remark = inp[start.offset..],
        }, start.loc, self.loc.back())),
        .angleo => try tx.append(attach(.angleo, self.loc.back(), self.loc.back())),
        .anglec => try tx.append(attach(.anglec, self.loc.back(), self.loc.back())),
    }

    return tx.toOwnedSlice();
}

fn attach(payload: Token.Payload, start: Loc, end: Loc) Token {
    return .{
        .payload = payload,
        .range = .{
            .start = start,
            .end = end,
        },
    };
}

fn resolveIntegral(s: []const u8) !Token.Payload {
    const n = try std.fmt.parseInt(isize, s, 10);
    if (n >= std.math.minInt(i16) and n <= std.math.maxInt(i16)) {
        return .{ .integer = @intCast(n) };
    } else if (n >= std.math.minInt(i32) and n <= std.math.maxInt(i32)) {
        return .{ .long = @intCast(n) };
    } else {
        return .{ .double = @floatFromInt(n) };
    }
}

fn resolveFloating(s: []const u8) !Token.Payload {
    // This is an ugly heuristic, but it approximates QBASIC's ...
    return if (s.len > 8)
        .{ .double = try std.fmt.parseFloat(f64, s) }
    else
        .{ .single = try std.fmt.parseFloat(f32, s) };
}

// TODO: replace with table (same with other direction above).
fn classifyBareword(bw: []const u8) Token.Payload {
    if (std.ascii.eqlIgnoreCase(bw, "if")) {
        return .kw_if;
    } else if (std.ascii.eqlIgnoreCase(bw, "then")) {
        return .kw_then;
    } else if (std.ascii.eqlIgnoreCase(bw, "elseif")) {
        return .kw_elseif;
    } else if (std.ascii.eqlIgnoreCase(bw, "else")) {
        return .kw_else;
    } else if (std.ascii.eqlIgnoreCase(bw, "end")) {
        return .kw_end;
    } else if (std.ascii.eqlIgnoreCase(bw, "goto")) {
        return .kw_goto;
    } else if (std.ascii.eqlIgnoreCase(bw, "for")) {
        return .kw_for;
    } else if (std.ascii.eqlIgnoreCase(bw, "to")) {
        return .kw_to;
    } else if (std.ascii.eqlIgnoreCase(bw, "step")) {
        return .kw_step;
    } else if (std.ascii.eqlIgnoreCase(bw, "next")) {
        return .kw_next;
    } else if (std.ascii.eqlIgnoreCase(bw, "dim")) {
        return .kw_dim;
    } else if (std.ascii.eqlIgnoreCase(bw, "as")) {
        return .kw_as;
    } else if (std.ascii.eqlIgnoreCase(bw, "gosub")) {
        return .kw_gosub;
    } else if (std.ascii.eqlIgnoreCase(bw, "return")) {
        return .kw_return;
    } else if (std.ascii.eqlIgnoreCase(bw, "stop")) {
        return .kw_stop;
    } else if (std.ascii.eqlIgnoreCase(bw, "do")) {
        return .kw_do;
    } else if (std.ascii.eqlIgnoreCase(bw, "loop")) {
        return .kw_loop;
    } else if (std.ascii.eqlIgnoreCase(bw, "while")) {
        return .kw_while;
    } else if (std.ascii.eqlIgnoreCase(bw, "until")) {
        return .kw_until;
    } else if (std.ascii.eqlIgnoreCase(bw, "wend")) {
        return .kw_wend;
    } else if (std.ascii.eqlIgnoreCase(bw, "let")) {
        return .kw_let;
    } else if (std.ascii.eqlIgnoreCase(bw, "and")) {
        return .kw_and;
    } else if (std.ascii.eqlIgnoreCase(bw, "or")) {
        return .kw_or;
    } else if (std.ascii.eqlIgnoreCase(bw, "xor")) {
        return .kw_xor;
    } else {
        return .{ .label = bw };
    }
}

fn expectTokens(input: []const u8, expected: []const Token) !void {
    const tx = try tokenize(testing.allocator, input, null);
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(expected, tx);
}

test "tokenizes basics" {
    try expectTokens(
        \\if 10 Then END;
        \\  tere maailm%, ava$ = siin& 'okok
        \\Awawa: #7<<>>
        \\REM Hiii :3
        \\REM
    , &.{
        Token.init(.kw_if, Range.init(.{ 1, 1 }, .{ 1, 2 })),
        Token.init(.{ .integer = 10 }, Range.init(.{ 1, 4 }, .{ 1, 5 })),
        Token.init(.kw_then, Range.init(.{ 1, 7 }, .{ 1, 10 })),
        Token.init(.kw_end, Range.init(.{ 1, 12 }, .{ 1, 14 })),
        Token.init(.semicolon, Range.init(.{ 1, 15 }, .{ 1, 15 })),
        Token.init(.linefeed, Range.init(.{ 1, 16 }, .{ 1, 16 })),
        Token.init(.{ .label = "tere" }, Range.init(.{ 2, 3 }, .{ 2, 6 })),
        Token.init(.{ .label = "maailm%" }, Range.init(.{ 2, 8 }, .{ 2, 14 })),
        Token.init(.comma, Range.init(.{ 2, 15 }, .{ 2, 15 })),
        Token.init(.{ .label = "ava$" }, Range.init(.{ 2, 17 }, .{ 2, 20 })),
        Token.init(.equals, Range.init(.{ 2, 22 }, .{ 2, 22 })),
        Token.init(.{ .label = "siin&" }, Range.init(.{ 2, 24 }, .{ 2, 28 })),
        Token.init(.{ .remark = "'okok" }, Range.init(.{ 2, 30 }, .{ 2, 34 })),
        Token.init(.linefeed, Range.init(.{ 2, 35 }, .{ 2, 35 })),
        Token.init(.{ .jumplabel = "Awawa:" }, Range.init(.{ 3, 1 }, .{ 3, 6 })),
        Token.init(.{ .fileno = 7 }, Range.init(.{ 3, 8 }, .{ 3, 9 })),
        Token.init(.angleo, Range.init(.{ 3, 10 }, .{ 3, 10 })),
        Token.init(.diamond, Range.init(.{ 3, 11 }, .{ 3, 12 })),
        Token.init(.anglec, Range.init(.{ 3, 13 }, .{ 3, 13 })),
        Token.init(.linefeed, Range.init(.{ 3, 14 }, .{ 3, 14 })),
        Token.init(.{ .remark = "REM Hiii :3" }, Range.init(.{ 4, 1 }, .{ 4, 11 })),
        Token.init(.linefeed, Range.init(.{ 4, 12 }, .{ 4, 12 })),
        Token.init(.{ .remark = "REM" }, Range.init(.{ 5, 1 }, .{ 5, 3 })),
    });
}

test "tokenizes strings" {
    // There is no escape.
    try expectTokens(
        \\"abc" "!"
    , &.{
        Token.init(.{ .string = "abc" }, Range.init(.{ 1, 1 }, .{ 1, 5 })),
        Token.init(.{ .string = "!" }, Range.init(.{ 1, 7 }, .{ 1, 9 })),
    });
}

test "tokenizes SINGLEs" {
    try expectTokens(
        \\1. 2.2 3! 4.! 5.5!
    , &.{
        Token.init(.{ .single = 1.0 }, Range.init(.{ 1, 1 }, .{ 1, 2 })),
        Token.init(.{ .single = 2.2 }, Range.init(.{ 1, 4 }, .{ 1, 6 })),
        Token.init(.{ .single = 3.0 }, Range.init(.{ 1, 8 }, .{ 1, 9 })),
        Token.init(.{ .single = 4.0 }, Range.init(.{ 1, 11 }, .{ 1, 13 })),
        Token.init(.{ .single = 5.5 }, Range.init(.{ 1, 15 }, .{ 1, 18 })),
    });
}

test "tokenizes DOUBLEs" {
    try expectTokens(
        \\1.2345678 2# 2147483648 3.45#
    , &.{
        Token.init(.{ .double = 1.2345678 }, Range.init(.{ 1, 1 }, .{ 1, 9 })),
        Token.init(.{ .double = 2.0 }, Range.init(.{ 1, 11 }, .{ 1, 12 })),
        Token.init(.{ .double = 2147483648.0 }, Range.init(.{ 1, 14 }, .{ 1, 23 })),
        Token.init(.{ .double = 3.45 }, Range.init(.{ 1, 25 }, .{ 1, 29 })),
    });
}
