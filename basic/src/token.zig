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

        pub fn initRange(t: T, start: struct { usize, usize }, end: struct { usize, usize }) Self {
            return init(t, .{
                .start = .{ .row = start[0], .col = start[1] },
                .end = .{ .row = end[0], .col = end[1] },
            });
        }
    };
}

const TokenPayload =
    union(enum) {
    number: i64,
    label: []const u8,
    string: []const u8, // XXX: uninterpreted.
    jumplabel: []const u8,
    fileno: usize, // XXX: doesn't support variable
    linefeed,
    comma,
    semicolon,
    equals,
    plus,
    minus,
    asterisk,
    fslash,
    pareno,
    parenc,
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
};

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
};

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

    fn feed(self: *Tokenizer, allocator: Allocator, s: []const u8) ![]Token {
        var tx = std.ArrayList(Token).init(allocator);
        errdefer tx.deinit();

        var state: State = .init;
        var i: usize = 0;
        var rewind = false;
        while (i < s.len) : ({
            if (rewind) {
                rewind = false;
            } else {
                if (s[i] == '\n') {
                    self.loc.row += 1;
                    self.loc.col = 1;
                } else {
                    self.loc.col += 1;
                }
                i += 1;
            }
        }) {
            const c = s[i];

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
                    } else if (c == ',') {
                        try tx.append(attach(.comma, self.loc, self.loc));
                    } else if (c == ';') {
                        try tx.append(attach(.semicolon, self.loc, self.loc));
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
                            .number = try std.fmt.parseInt(isize, s[start.offset..i], 10),
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
                        try tx.append(attach(.{ .label = s[start.offset .. i + 1] }, start.loc, self.loc));
                        state = .init;
                    } else if (c == ':') {
                        try tx.append(attach(.{ .jumplabel = s[start.offset..i] }, start.loc, self.loc));
                        state = .init;
                    } else {
                        try tx.append(attach(classifyBareword(s[start.offset..i]), start.loc, self.loc.back()));
                        state = .init;
                        rewind = true;
                    }
                },
                .string => |start| {
                    if (c == '"') {
                        try tx.append(attach(.{ .string = s[start.offset .. i + 1] }, start.loc, self.loc));
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
                            .fileno = try std.fmt.parseInt(usize, s[start.offset + 1 .. i], 10),
                        }, start.loc, self.loc.back()));
                        state = .init;
                        rewind = true;
                    }
                },
            }
        }

        switch (state) {
            .init => {},
            .number => |start| try tx.append(attach(.{
                .number = try std.fmt.parseInt(isize, s[start.offset..], 10),
            }, start.loc, self.loc.back())),
            .bareword => |start| try tx.append(attach(classifyBareword(s[start.offset..]), start.loc, self.loc.back())),
            .string => return Error.UnexpectedEnd,
            .fileno => |start| try tx.append(attach(.{
                .fileno = try std.fmt.parseInt(usize, s[start.offset + 1 ..], 10),
            }, start.loc, self.loc.back())),
        }

        return tx.toOwnedSlice();
    }
};

pub fn tokenize(allocator: Allocator, s: []const u8) ![]Token {
    var t = Tokenizer{};
    return t.feed(allocator, s);
}

test "tokenizes basics" {
    const tx = try tokenize(testing.allocator,
        \\10 if Then END
        \\  tere maailm%, ava$ = siin&
        \\Awawa: #7
    );
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(&[_]Token{
        Token.initRange(.{ .number = 10 }, .{ 1, 1 }, .{ 1, 2 }),
        Token.initRange(.kw_if, .{ 1, 4 }, .{ 1, 5 }),
        Token.initRange(.kw_then, .{ 1, 7 }, .{ 1, 10 }),
        Token.initRange(.kw_end, .{ 1, 12 }, .{ 1, 14 }),
        Token.initRange(.linefeed, .{ 1, 15 }, .{ 1, 15 }),
        Token.initRange(.{ .label = "tere" }, .{ 2, 3 }, .{ 2, 6 }),
        Token.initRange(.{ .label = "maailm%" }, .{ 2, 8 }, .{ 2, 14 }),
        Token.initRange(.comma, .{ 2, 15 }, .{ 2, 15 }),
        Token.initRange(.{ .label = "ava$" }, .{ 2, 17 }, .{ 2, 20 }),
        Token.initRange(.equals, .{ 2, 22 }, .{ 2, 22 }),
        Token.initRange(.{ .label = "siin&" }, .{ 2, 24 }, .{ 2, 28 }),
        Token.initRange(.linefeed, .{ 2, 29 }, .{ 2, 29 }),
        Token.initRange(.{ .jumplabel = "Awawa" }, .{ 3, 1 }, .{ 3, 6 }),
        Token.initRange(.{ .fileno = 7 }, .{ 3, 8 }, .{ 3, 9 }),
    }, tx);
}
