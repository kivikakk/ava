const std = @import("std");
const testing = std.testing;

// Any references belong to the input string.
const Token = union(enum) {
    number: i64,
    label: []const u8,
    string: []const u8,
    comma,
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

const Error = error{
    UnexpectedChar,
    UnexpectedEnd,
};

const State = union(enum) {
    init: void,
    number: usize,
    bareword: usize,
    string: usize,
};

fn tokenizeBareword(bw: []const u8) Token {
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

fn tokenize(allocator: std.mem.Allocator, s: []const u8) (std.mem.Allocator.Error || std.fmt.ParseIntError || Error)![]Token {
    var tx = std.ArrayList(Token).init(allocator);
    errdefer tx.deinit();

    var state: State = .init;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];

        switch (state) {
            .init => {
                if (c >= '0' and c <= '9') {
                    state = .{ .number = i };
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    state = .{ .bareword = i };
                } else if (c == '"') {
                    state = .{ .string = i };
                } else if (c == ' ') {
                    // nop
                } else if (c == ',') {
                    try tx.append(.comma);
                } else if (c == '=') {
                    try tx.append(.equals);
                } else if (c == '+') {
                    try tx.append(.plus);
                } else if (c == '-') {
                    try tx.append(.minus);
                } else if (c == '*') {
                    try tx.append(.asterisk);
                } else if (c == '/') {
                    try tx.append(.fslash);
                } else if (c == '(') {
                    try tx.append(.pareno);
                } else if (c == ')') {
                    try tx.append(.parenc);
                } else {
                    return error.UnexpectedChar;
                }
            },
            .number => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    return error.UnexpectedChar;
                } else {
                    try tx.append(.{
                        .number = try std.fmt.parseInt(isize, s[start..i], 10),
                    });
                    state = .init;
                    // rewind
                    i -= 1;
                }
            },
            .bareword => |start| {
                if (c >= '0' and c <= '9') {
                    // nop
                } else if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                    // nop
                } else if (c == '$' or c == '%' or c == '&') {
                    try tx.append(.{ .label = s[start .. i + 1] });
                    state = .init;
                } else {
                    try tx.append(tokenizeBareword(s[start..i]));
                    state = .init;
                    // rewind
                    i -= 1;
                }
            },
            .string => |start| {
                if (c == '"') {
                    try tx.append(.{ .string = s[start .. i + 1] });
                    state = .init;
                } else {
                    // nop
                }
            },
        }
    }

    switch (state) {
        .init => {},
        .number => |start| try tx.append(.{
            .number = try std.fmt.parseInt(isize, s[start..], 10),
        }),
        .bareword => |start| try tx.append(tokenizeBareword(s[start..])),
        .string => return error.UnexpectedEnd,
    }

    return tx.toOwnedSlice();
}

test "tokenizes basics" {
    const tx = try tokenize(testing.allocator, "10 if Then END tere maailm%, ava$ = siin&");
    defer testing.allocator.free(tx);

    try testing.expectEqualDeep(&[_]Token{
        .{ .number = 10 },
        .kw_if,
        .kw_then,
        .kw_end,
        .{ .label = "tere" },
        .{ .label = "maailm%" },
        .comma,
        .{ .label = "ava$" },
        .equals,
        .{ .label = "siin&" },
    }, tx);
}
