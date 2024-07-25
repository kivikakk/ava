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
    lte,
    gte,
    @"and",
    @"or",
    xor,
};

pub const ExprPayload = union(enum) {
    const Self = @This();

    imm_number: isize,
    imm_string: []const u8,
    label: []const u8,
    binop: struct {
        lhs: *Expr,
        op: Op,
        rhs: *Expr,
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

pub const Expr = WithRange(ExprPayload);

pub const StmtPayload = union(enum) {
    const Self = @This();

    remark: []const u8,
    call: struct {
        name: WithRange([]const u8),
        args: []const Expr,
    },
    let: struct {
        kw: bool,
        lhs: WithRange([]const u8),
        rhs: Expr,
    },
    @"if": struct {
        cond: Expr,
    },
    if1: struct {
        cond: Expr,
        stmt: *Stmt,
    },
    end,
    endif,

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
            .if1 => |i| {
                i.cond.payload.deinit(allocator);
                i.stmt.payload.deinit(allocator);
                allocator.destroy(i.stmt);
            },
            .end => {},
            .endif => {},
        }
    }
};

pub const Stmt = WithRange(StmtPayload);

pub const Error = error{
    ExpectedTerminator,
    UnexpectedToken,
    UnexpectedEnd,
};

const State = union(enum) {
    init,
    call: struct {
        label: WithRange([]const u8),
        args: std.ArrayList(Expr),
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
    nti: usize = 0,
    sx: std.ArrayListUnmanaged(Stmt) = .{},
    pending_rem: ?Stmt = null,

    fn init(allocator: Allocator, inp: []const u8) !Self {
        const tx = try token.tokenize(allocator, inp);
        return .{
            .allocator = allocator,
            .tx = tx,
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.tx);
        for (self.sx.items) |s|
            s.payload.deinit(self.allocator);
        self.sx.deinit(self.allocator);
        if (self.pending_rem) |s|
            s.payload.deinit(self.allocator);
    }

    fn append(self: *Self, s: Stmt) !void {
        try self.sx.append(self.allocator, s);
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

    fn acceptTerminator(self: *Self) !bool {
        if (self.accept(.remark)) |r| {
            std.debug.assert(self.pending_rem == null);
            self.pending_rem = Stmt.init(.{ .remark = r.payload }, r.range);
        }

        return self.accept(.linefeed) != null or
            self.accept(.colon) != null;
    }

    fn acceptFactor(self: *Self) ?Expr {
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

    // TODO: comptime wonk to define accept(Term,Expr,Cond) in common?
    fn acceptTerm(self: *Self) !?Expr {
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

        const lhs = try self.allocator.create(Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = f;
        const rhs = try self.allocator.create(Expr);
        rhs.* = f2;

        return Expr.initEnds(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, f.range, f2.range);
    }

    fn acceptExpr(self: *Self) !?Expr {
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

        const lhs = try self.allocator.create(Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = t;
        const rhs = try self.allocator.create(Expr);
        rhs.* = t2;

        return Expr.initEnds(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, t.range, t2.range);
    }

    fn acceptCond(self: *Self) !?Expr {
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
                break :op .gt
            else if (self.accept(.lte) != null)
                break :op .lte
            else if (self.accept(.gte) != null)
                break :op .gte;
            return e;
        };
        const e2 = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer e2.payload.deinit(self.allocator);

        const lhs = try self.allocator.create(Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = e;
        const rhs = try self.allocator.create(Expr);
        rhs.* = e2;

        return Expr.initEnds(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, e.range, e2.range);
    }

    fn acceptExprList(self: *Self) !?[]Expr {
        const e = try self.acceptExpr() orelse return null;
        errdefer e.payload.deinit(self.allocator);

        var ex = std.ArrayList(Expr).init(self.allocator);
        errdefer ex.deinit();

        try ex.append(e);

        while (self.accept(.comma) != null) {
            const e2 = try self.acceptExpr() orelse
                return Error.UnexpectedToken;
            try ex.append(e2);
        }

        if (!try self.acceptTerminator())
            return Error.ExpectedTerminator;

        return try ex.toOwnedSlice();
    }

    fn parseOne(self: *Self) !?Stmt {
        if (self.eoi())
            return null;

        if (self.accept(.linefeed) != null)
            return self.parseOne();

        if (self.accept(.remark)) |r| {
            try self.append(Stmt.init(.{ .remark = r.payload }, r.range));
            return self.parseOne();
        }

        if (self.accept(.label)) |l| {
            if (try self.acceptTerminator()) {
                return Stmt.init(.{ .call = .{
                    .name = l,
                    .args = &.{},
                } }, l.range);
            }

            if (try self.acceptExprList()) |ex| {
                return Stmt.initEnds(.{ .call = .{
                    .name = l,
                    .args = ex,
                } }, l.range, ex[ex.len - 1].range);
            }

            if (self.accept(.equals) != null) {
                const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
                return Stmt.initEnds(.{ .let = .{
                    .kw = false,
                    .lhs = l,
                    .rhs = rhs,
                } }, l.range, rhs.range);
            }

            if (self.eoi())
                return Error.UnexpectedEnd;

            return Error.UnexpectedToken;
        }

        if (self.accept(.kw_let)) |k| {
            const lhs = try self.expect(.label);
            _ = try self.expect(.equals);
            const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
            return Stmt.initEnds(.{ .let = .{
                .kw = true,
                .lhs = lhs,
                .rhs = rhs,
            } }, k.range, rhs.range);
        }

        if (self.accept(.kw_if)) |k| {
            const cond = try self.acceptCond() orelse return Error.UnexpectedToken;
            errdefer cond.payload.deinit(self.allocator);
            _ = try self.expect(.kw_then);
            // TODO: remarks anywhere, including here.
            // TODO: same line IF .. THEN ... [ELSE ...]
            if (self.accept(.linefeed) != null) {
                return Stmt.initEnds(.{ .@"if" = .{
                    .cond = cond,
                } }, k.range, cond.range);
            }
            const s = try self.parseOne() orelse return Error.UnexpectedEnd;
            errdefer s.payload.deinit(self.allocator);
            const stmt = try self.allocator.create(Stmt);
            stmt.* = s;
            return Stmt.initEnds(.{ .if1 = .{
                .cond = cond,
                .stmt = stmt,
            } }, k.range, stmt.range);
        }

        if (self.accept(.kw_end)) |k| {
            if (self.accept(.kw_if)) |k2| {
                if (!try self.acceptTerminator())
                    return Error.ExpectedTerminator;
                return Stmt.initEnds(.endif, k.range, k2.range);
            }
            if (!try self.acceptTerminator())
                return Error.ExpectedTerminator;
            return Stmt.init(.end, k.range);
        }

        return Error.UnexpectedToken;
    }

    fn parseAll(self: *Self) ![]Stmt {
        while (try self.parseOne()) |s| {
            errdefer s.payload.deinit(self.allocator);
            try self.append(s);
            // XXX: double free on error in pending_rem append.
            if (self.pending_rem) |r|
                try self.append(r);
            self.pending_rem = null;
        }

        return self.sx.toOwnedSlice(self.allocator);
    }
};

pub fn parse(allocator: Allocator, inp: []const u8) ![]Stmt {
    var p = try Parser.init(allocator, inp);
    defer p.deinit();

    return p.parseAll();
}

pub fn freeStmts(allocator: Allocator, sx: []Stmt) void {
    for (sx) |s| s.payload.deinit(allocator);
    allocator.free(sx);
}

test "parses a nullary statement" {
    const sx = try parse(testing.allocator, "PRINT\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{
        Stmt.initRange(.{ .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        } }, .{ 1, 1 }, .{ 1, 5 }),
    });
}

test "parses a unary statement" {
    const sx = try parse(testing.allocator, "\n PRINT 42\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{
        Stmt.initRange(.{ .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 2, 2 }, .{ 2, 6 }),
            .args = &.{
                Expr.initRange(.{ .imm_number = 42 }, .{ 2, 8 }, .{ 2, 9 }),
            },
        } }, .{ 2, 2 }, .{ 2, 9 }),
    });
}

test "parses a binary statement" {
    const sx = try parse(testing.allocator, "PRINT X$, Y%\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{
        Stmt.initRange(.{ .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{
                Expr.initRange(.{ .label = "X$" }, .{ 1, 7 }, .{ 1, 8 }),
                Expr.initRange(.{ .label = "Y%" }, .{ 1, 11 }, .{ 1, 12 }),
            },
        } }, .{ 1, 1 }, .{ 1, 12 }),
    });
}
