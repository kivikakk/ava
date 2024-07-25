const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Loc = struct {
    row: usize,
    col: usize,

    fn back(self: Loc) Loc {
        std.debug.assert(self.col > 1);
        return .{ .row = self.row, .col = self.col - 1 };
    }
};

pub const Range = struct {
    start: Loc,
    end: Loc,
};

pub fn WithRange(comptime T: type) type {
    return struct {
        const Self = @This();

        payload: T,
        range: Range,

        pub fn init(t: T, range: Range) Self {
            return .{
                .payload = t,
                .range = range,
            };
        }

        pub fn initEnds(t: T, r1: Range, r2: Range) Self {
            return init(t, .{ .start = r1.start, .end = r2.end });
        }

        pub fn initRange(t: T, start: struct { usize, usize }, end: struct { usize, usize }) Self {
            return init(t, .{
                .start = .{ .row = start[0], .col = start[1] },
                .end = .{ .row = end[0], .col = end[1] },
            });
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try std.fmt.format(writer, "<{d}:{d}-{d}:{d}> {any}", .{
                self.range.start.row,
                self.range.start.col,
                self.range.end.row,
                self.range.end.col,
                self.payload,
            });
        }
    };
}

pub const TokenPayload = union(enum) {
    const Self = @This();

    number: i64,
    label: []const u8,
    remark: []const u8,
    string: []const u8, // XXX: uninterpreted.
    jumplabel: []const u8,
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

pub const TokenTag = std.meta.Tag(TokenPayload);

// Any references belong to the input string.
pub const Token = WithRange(TokenPayload);

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
    number: LocOffset,
    bareword: LocOffset,
    string: LocOffset,
    fileno: LocOffset,
    remark: LocOffset,
    angleo,
    anglec,
};

// TODO: replace with table (same with other direction above).
fn classifyBareword(bw: []const u8) TokenPayload {
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

const Tokenizer = struct {
    loc: Loc = .{ .row = 1, .col = 1 },

    fn attach(payload: TokenPayload, start: Loc, end: Loc) Token {
        return .{
            .payload = payload,
            .range = .{
                .start = start,
                .end = end,
            },
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
                        state = .{ .number = .{ .loc = self.loc, .offset = i } };
                    } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        state = .{ .bareword = .{ .loc = self.loc, .offset = i } };
                    } else if (c == '"') {
                        state = .{ .string = .{ .loc = self.loc, .offset = i } };
                    } else if (c == ' ') {
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
                .number => |start| {
                    if (c >= '0' and c <= '9') {
                        // nop
                    } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        return Error.UnexpectedChar;
                    } else {
                        try tx.append(attach(.{
                            .number = try std.fmt.parseInt(isize, inp[start.offset..i], 10),
                        }, start.loc, self.loc.back()));
                        state = .init;
                        rewind = true;
                    }
                },
                .bareword => |start| {
                    if (c >= '0' and c <= '9') {
                        // nop
                    } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        // nop
                    } else if (c == '$' or c == '%' or c == '&') {
                        try tx.append(attach(.{ .label = inp[start.offset .. i + 1] }, start.loc, self.loc));
                        state = .init;
                    } else if (c == ':') {
                        try tx.append(attach(.{ .jumplabel = inp[start.offset..i] }, start.loc, self.loc));
                        state = .init;
                    } else {
                        try tx.append(attach(classifyBareword(inp[start.offset..i]), start.loc, self.loc.back()));
                        state = .init;
                        rewind = true;
                    }
                },
                .string => |start| {
                    if (c == '"') {
                        try tx.append(attach(.{ .string = inp[start.offset .. i + 1] }, start.loc, self.loc));
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
                            .remark = inp[start.offset + 1 .. i],
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
            .number => |start| try tx.append(attach(.{
                .number = try std.fmt.parseInt(isize, inp[start.offset..], 10),
            }, start.loc, self.loc.back())),
            .bareword => |start| try tx.append(attach(classifyBareword(inp[start.offset..]), start.loc, self.loc.back())),
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
};

pub fn tokenize(allocator: Allocator, inp: []const u8) ![]Token {
    var t = Tokenizer{};
    return t.feed(allocator, inp);
}

test "tokenizes basics" {
    const tx = try tokenize(testing.allocator,
        \\if 10 Then END
        \\  tere maailm%, ava$ = siin& 'okok
        \\Awawa: #7<<>>
    );
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(&[_]Token{
        Token.initRange(.kw_if, .{ 1, 1 }, .{ 1, 2 }),
        Token.initRange(.{ .number = 10 }, .{ 1, 4 }, .{ 1, 5 }),
        Token.initRange(.kw_then, .{ 1, 7 }, .{ 1, 10 }),
        Token.initRange(.kw_end, .{ 1, 12 }, .{ 1, 14 }),
        Token.initRange(.linefeed, .{ 1, 15 }, .{ 1, 15 }),
        Token.initRange(.{ .label = "tere" }, .{ 2, 3 }, .{ 2, 6 }),
        Token.initRange(.{ .label = "maailm%" }, .{ 2, 8 }, .{ 2, 14 }),
        Token.initRange(.comma, .{ 2, 15 }, .{ 2, 15 }),
        Token.initRange(.{ .label = "ava$" }, .{ 2, 17 }, .{ 2, 20 }),
        Token.initRange(.equals, .{ 2, 22 }, .{ 2, 22 }),
        Token.initRange(.{ .label = "siin&" }, .{ 2, 24 }, .{ 2, 28 }),
        Token.initRange(.{ .remark = "okok" }, .{ 2, 30 }, .{ 2, 34 }),
        Token.initRange(.linefeed, .{ 2, 35 }, .{ 2, 35 }),
        Token.initRange(.{ .jumplabel = "Awawa" }, .{ 3, 1 }, .{ 3, 6 }),
        Token.initRange(.{ .fileno = 7 }, .{ 3, 8 }, .{ 3, 9 }),
        Token.initRange(.angleo, .{ 3, 10 }, .{ 3, 10 }),
        Token.initRange(.diamond, .{ 3, 11 }, .{ 3, 12 }),
        Token.initRange(.anglec, .{ 3, 13 }, .{ 3, 13 }),
    }, tx);
}
