const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const token = @import("token.zig");
const WithRange = token.WithRange;

pub const Op = enum {
    mul,
    div,
    add,
    sub,
    eq,
    neq,
    lt,
    gt,
    // TODO: lte gte
    @"and",
    @"or",
    xor,
};

pub const Expr = union(enum) {
    const Self = @This();

    imm_number: isize,
    imm_string: []const u8,
    label: []const u8,
    binop: struct {
        lhs: *WithRange(Expr),
        op: Op,
        rhs: *WithRange(Expr),
    },

    fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .imm_number => {},
            .imm_string => {},
            .label => {},
            .binop => |b| {
                b.lhs.payload.deinit(allocator);
                b.rhs.payload.deinit(allocator);
                allocator.destroy(b.lhs);
                allocator.destroy(b.rhs);
            },
        }
    }
};

pub const Stmt = union(enum) {
    const Self = @This();

    remark: WithRange([]const u8),
    call: struct {
        name: WithRange([]const u8),
        args: []const WithRange(Expr),
    },
    let: struct {
        kw: ?WithRange(void),
        lhs: WithRange([]const u8),
        rhs: WithRange(Expr),
    },
    @"if": struct {
        kw: WithRange(void),
        cond: WithRange(Expr),
    },
    end: WithRange(void),
    endif: WithRange(void),

    fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .remark => {},
            .call => |c| {
                for (c.args) |e|
                    e.payload.deinit(allocator);
                allocator.free(c.args);
            },
            .let => |l| l.rhs.payload.deinit(allocator),
            .@"if" => |i| i.cond.payload.deinit(allocator),
            .end => {},
            .endif => {},
        }
    }
};

pub const Error = error{
    UnexpectedToken,
    ExpectedEnd,
};

const State = union(enum) {
    init,
    call: struct {
        label: WithRange([]const u8),
        args: std.ArrayList(WithRange(Expr)),
        comma_next: bool,
    },

    fn deinit(self: State) void {
        switch (self) {
            .init => {},
            .call => |c| {
                c.args.deinit();
            },
        }
    }
};

const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    tx: []token.Token,
    nti: usize,

    fn init(allocator: Allocator, inp: []const u8) !Self {
        const tx = try token.tokenize(allocator, inp);
        return .{
            .allocator = allocator,
            .tx = tx,
            .nti = 0,
        };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.tx);
    }

    fn eoi(self: *const Self) bool {
        return self.nti == self.tx.len;
    }

    fn nt(self: *const Self) ?token.Token {
        if (self.eoi())
            return null;
        return self.tx[self.nti];
    }

    fn accept(self: *Self, comptime tt: token.TokenTag) ?WithRange(std.meta.TagPayload(token.TokenPayload, tt)) {
        const t = self.nt() orelse return null;
        if (t.payload == tt) {
            self.nti += 1;
            const payload = @field(t.payload, @tagName(tt));
            return WithRange(std.meta.TagPayload(token.TokenPayload, tt))
                .init(payload, t.range);
        }
        return null;
    }

    fn expect(self: *Self, comptime tt: token.TokenTag) !WithRange(std.meta.TagPayload(token.TokenPayload, tt)) {
        return self.accept(tt) orelse Error.UnexpectedToken;
    }

    fn acceptEnd(self: *Self) bool {
        return self.eoi() or
            self.accept(.linefeed) != null or
            self.accept(.semicolon) != null;
    }

    fn acceptFactor(self: *Self) ?WithRange(Expr) {
        if (self.accept(.number)) |n| {
            return .{
                .payload = .{ .imm_number = n.payload },
                .range = n.range,
            };
        }
        if (self.accept(.label)) |l| {
            return .{
                .payload = .{ .label = l.payload },
                .range = l.range,
            };
        }
        if (self.accept(.string)) |s| {
            return .{
                .payload = .{ .imm_string = s.payload },
                .range = s.range,
            };
        }
        // TODO: pareno
        return null;
    }

    fn acceptTerm(self: *Self) !?WithRange(Expr) {
        const f = self.acceptFactor() orelse return null;
        errdefer f.payload.deinit(self.allocator);
        const op: Op = op: {
            if (self.accept(.asterisk) != null)
                break :op .mul
            else if (self.accept(.fslash) != null)
                break :op .div;
            return f;
        };
        const f2 = self.acceptFactor() orelse return Error.UnexpectedToken;
        errdefer f2.payload.deinit(self.allocator);

        const lhs = try self.allocator.create(WithRange(Expr));
        errdefer self.allocator.destroy(lhs);
        lhs.* = f;
        const rhs = try self.allocator.create(WithRange(Expr));
        rhs.* = f2;

        return WithRange(Expr).initBin(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, f.range, f2.range);
    }

    fn acceptExpr(self: *Self) !?WithRange(Expr) {
        const t = try self.acceptTerm() orelse return null;
        errdefer t.payload.deinit(self.allocator);
        const op: Op = op: {
            if (self.accept(.plus) != null)
                break :op .add
            else if (self.accept(.minus) != null)
                break :op .sub;
            return t;
        };
        const t2 = try self.acceptTerm() orelse return Error.UnexpectedToken;
        errdefer t2.payload.deinit(self.allocator);

        const lhs = try self.allocator.create(WithRange(Expr));
        errdefer self.allocator.destroy(lhs);
        lhs.* = t;
        const rhs = try self.allocator.create(WithRange(Expr));
        rhs.* = t2;

        return WithRange(Expr).initBin(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, t.range, t2.range);
    }

    fn acceptCond(self: *Self) !?WithRange(Expr) {
        const e = try self.acceptExpr() orelse return null;
        errdefer e.payload.deinit(self.allocator);
        const op: Op = op: {
            if (self.accept(.equals) != null)
                break :op .eq
            else if (self.accept(.diamond) != null)
                break :op .neq
            else if (self.accept(.angleo) != null)
                break :op .lt
            else if (self.accept(.anglec) != null)
                break :op .gt;
            return e;
        };
        const e2 = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer e2.payload.deinit(self.allocator);

        const lhs = try self.allocator.create(WithRange(Expr));
        errdefer self.allocator.destroy(lhs);
        lhs.* = e;
        const rhs = try self.allocator.create(WithRange(Expr));
        rhs.* = e2;

        return WithRange(Expr).initBin(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, e.range, e2.range);
    }

    fn acceptExprList(self: *Self) !?[]WithRange(Expr) {
        const e = try self.acceptExpr() orelse return null;

        var ex = std.ArrayList(WithRange(Expr)).init(self.allocator);
        errdefer ex.deinit();

        try ex.append(e);

        while (self.accept(.comma) != null) {
            const e2 = try self.acceptExpr() orelse
                return Error.UnexpectedToken;
            try ex.append(e2);
        }

        if (!self.acceptEnd())
            return Error.ExpectedEnd;

        return try ex.toOwnedSlice();
    }

    fn parseOne(self: *Self) !?Stmt {
        if (self.eoi())
            return null;

        if (self.accept(.linefeed) != null)
            return self.parseOne();

        if (self.accept(.remark)) |r|
            return .{ .remark = r };

        if (self.accept(.label)) |l| {
            if (self.acceptEnd()) {
                return .{ .call = .{
                    .name = l,
                    .args = &.{},
                } };
            }

            if (try self.acceptExprList()) |ex| {
                return .{ .call = .{
                    .name = l,
                    .args = ex,
                } };
            }

            if (self.accept(.equals) != null) {
                const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
                return .{ .let = .{
                    .kw = null,
                    .lhs = l,
                    .rhs = rhs,
                } };
            }

            return Error.UnexpectedToken;
        }

        if (self.accept(.kw_let)) |k| {
            const lhs = try self.expect(.label);
            _ = try self.expect(.equals);
            const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
            return .{ .let = .{
                .kw = k,
                .lhs = lhs,
                .rhs = rhs,
            } };
        }

        if (self.accept(.kw_if)) |k| {
            const cond = try self.acceptCond() orelse return Error.UnexpectedToken;
            _ = try self.expect(.kw_then);
            // TODO: same line IF .. THEN ... [ELSE ...]
            // TODO: remarks anywhere, including here.
            _ = try self.expect(.linefeed);
            return .{ .@"if" = .{
                .kw = k,
                .cond = cond,
            } };
        }

        if (self.accept(.kw_end)) |k| {
            if (self.accept(.kw_if)) |k2| {
                if (!self.acceptEnd())
                    return Error.ExpectedEnd;
                return .{ .endif = WithRange(void).initBin({}, k.range, k2.range) };
            }
            if (!self.acceptEnd())
                return Error.ExpectedEnd;
            return .{ .end = k };
        }

        return Error.UnexpectedToken;
    }

    fn parseAll(self: *Self) ![]Stmt {
        var sx = std.ArrayList(Stmt).init(self.allocator);
        errdefer {
            for (sx.items) |s| s.deinit(self.allocator);
            sx.deinit();
        }

        while (try self.parseOne()) |s|
            try sx.append(s);

        return sx.toOwnedSlice();
    }
};

pub fn parse(allocator: Allocator, inp: []const u8) ![]Stmt {
    var p = try Parser.init(allocator, inp);
    defer p.deinit();

    return p.parseAll() catch |err| {
        if (p.nt()) |t| {
            std.debug.print("last token: {any}\n", .{t});
        } else {
            std.debug.print("reached EOF\n", .{});
        }
        return err;
    };
}

pub fn freeStmts(allocator: Allocator, sx: []Stmt) void {
    for (sx) |s| s.deinit(allocator);
    allocator.free(sx);
}

test "parses a nullary statement" {
    const sx = try parse(testing.allocator, "PRINT\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        },
    }});
}

test "parses a nullary statement without linefeed" {
    const sx = try parse(testing.allocator, "PRINT");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        },
    }});
}

test "parses a unary statement" {
    const sx = try parse(testing.allocator, "\n PRINT 42\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 2, 2 }, .{ 2, 6 }),
            .args = &.{
                WithRange(Expr).initRange(.{ .imm_number = 42 }, .{ 2, 8 }, .{ 2, 9 }),
            },
        },
    }});
}

test "parses a binary statement" {
    const sx = try parse(testing.allocator, "PRINT X$, Y%\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{
                WithRange(Expr).initRange(.{ .label = "X$" }, .{ 1, 7 }, .{ 1, 8 }),
                WithRange(Expr).initRange(.{ .label = "Y%" }, .{ 1, 11 }, .{ 1, 12 }),
            },
        },
    }});
}
