const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const token = @import("token.zig");
const loc = @import("loc.zig");
const WithRange = loc.WithRange;

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
        op: WithRange(Op),
        rhs: *Expr,
    },
    paren: *Expr,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .imm_number => {},
            .imm_string => {},
            .label => {},
            .binop => |b| {
                b.lhs.deinit(allocator);
                b.rhs.deinit(allocator);
                allocator.destroy(b.lhs);
                allocator.destroy(b.rhs);
            },
            .paren => |e| {
                e.deinit(allocator);
                allocator.destroy(e);
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
        tok_eq: WithRange(void),
        rhs: Expr,
    },
    @"if": struct {
        cond: Expr,
        tok_then: WithRange(void),
    },
    if1: struct {
        cond: Expr,
        tok_then: WithRange(void),
        stmt_t: *Stmt,
    },
    if2: struct {
        cond: Expr,
        tok_then: WithRange(void),
        stmt_t: *Stmt,
        tok_else: WithRange(void),
        stmt_f: *Stmt,
    },
    @"for": struct {
        lv: WithRange([]const u8),
        tok_eq: WithRange(void),
        from: Expr,
        tok_to: WithRange(void),
        to: Expr,
    },
    forstep: struct {
        lv: WithRange([]const u8),
        tok_eq: WithRange(void),
        from: Expr,
        tok_to: WithRange(void),
        to: Expr,
        tok_step: WithRange(void),
        step: Expr,
    },
    next: WithRange([]const u8),
    jumplabel: []const u8,
    goto: WithRange([]const u8),
    end,
    endif,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .remark => {},
            .call => |c| {
                for (c.args) |e|
                    e.deinit(allocator);
                allocator.free(c.args);
            },
            .let => |l| l.rhs.deinit(allocator),
            .@"if" => |i| i.cond.deinit(allocator),
            .if1 => |i| {
                i.cond.deinit(allocator);
                i.stmt_t.deinit(allocator);
                allocator.destroy(i.stmt_t);
            },
            .if2 => |i| {
                i.cond.deinit(allocator);
                i.stmt_t.deinit(allocator);
                allocator.destroy(i.stmt_t);
                i.stmt_f.deinit(allocator);
                allocator.destroy(i.stmt_f);
            },
            .@"for" => |f| {
                f.from.deinit(allocator);
                f.to.deinit(allocator);
            },
            .forstep => |f| {
                f.from.deinit(allocator);
                f.to.deinit(allocator);
                f.step.deinit(allocator);
            },
            .next => {},
            .jumplabel => {},
            .goto => {},
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
            s.deinit(self.allocator);
        self.sx.deinit(self.allocator);
        if (self.pending_rem) |s|
            s.deinit(self.allocator);
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

    fn peek(self: *Self, comptime tt: token.TokenTag) bool {
        const t = self.nt() orelse return false;
        return t.payload == tt;
    }

    fn peekTerminator(self: *Self) !bool {
        if (self.accept(.remark)) |r| {
            std.debug.assert(self.pending_rem == null);
            self.pending_rem = Stmt.init(.{ .remark = r.payload }, r.range);
        }

        return self.peek(.linefeed) or
            self.peek(.colon) or
            self.peek(.kw_else) or
            self.peek(.parenc);
    }

    fn acceptFactor(self: *Self) !?Expr {
        if (self.accept(.number)) |n|
            return Expr.init(.{ .imm_number = n.payload }, n.range);

        if (self.accept(.label)) |l|
            return Expr.init(.{ .label = l.payload }, l.range);

        if (self.accept(.string)) |s|
            return Expr.init(.{ .imm_string = s.payload }, s.range);

        if (self.accept(.pareno)) |p| {
            const e = try self.acceptExpr() orelse return Error.UnexpectedToken;
            errdefer e.deinit(self.allocator);
            const tok_pc = try self.expect(.parenc);

            const expr = try self.allocator.create(Expr);
            expr.* = e;
            return Expr.initEnds(.{ .paren = expr }, p.range, tok_pc.range);
        }

        return null;
    }

    // TODO: comptime wonk to define accept(Term,Expr,Cond) in common?
    fn acceptTerm(self: *Self) !?Expr {
        const f = try self.acceptFactor() orelse return null;
        errdefer f.deinit(self.allocator);
        const op = op: {
            if (self.accept(.asterisk)) |o|
                break :op WithRange(Op).init(.mul, o.range)
            else if (self.accept(.fslash)) |o|
                break :op WithRange(Op).init(.div, o.range);
            return f;
        };
        const f2 = try self.acceptFactor() orelse return Error.UnexpectedToken;
        errdefer f2.deinit(self.allocator);

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

    fn acceptExpr(self: *Self) (Allocator.Error || Error)!?Expr {
        const t = try self.acceptTerm() orelse return null;
        errdefer t.deinit(self.allocator);
        const op = op: {
            if (self.accept(.plus)) |o|
                break :op WithRange(Op).init(.add, o.range)
            else if (self.accept(.minus)) |o|
                break :op WithRange(Op).init(.sub, o.range);
            return t;
        };
        const t2 = try self.acceptTerm() orelse return Error.UnexpectedToken;
        errdefer t2.deinit(self.allocator);

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
        errdefer e.deinit(self.allocator);
        const op = op: {
            if (self.accept(.equals)) |o|
                break :op WithRange(Op).init(.eq, o.range)
            else if (self.accept(.diamond)) |o|
                break :op WithRange(Op).init(.neq, o.range)
            else if (self.accept(.angleo)) |o|
                break :op WithRange(Op).init(.lt, o.range)
            else if (self.accept(.anglec)) |o|
                break :op WithRange(Op).init(.gt, o.range)
            else if (self.accept(.lte)) |o|
                break :op WithRange(Op).init(.lte, o.range)
            else if (self.accept(.gte)) |o|
                break :op WithRange(Op).init(.gte, o.range);
            return e;
        };
        const e2 = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer e2.deinit(self.allocator);

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
        errdefer e.deinit(self.allocator);

        var ex = std.ArrayList(Expr).init(self.allocator);
        errdefer ex.deinit();

        try ex.append(e);

        while (self.accept(.comma) != null) {
            const e2 = try self.acceptExpr() orelse
                return Error.UnexpectedToken;
            try ex.append(e2);
        }

        if (!try self.peekTerminator())
            return Error.ExpectedTerminator;

        return try ex.toOwnedSlice();
    }

    fn acceptStmtLabel(self: *Self) !?Stmt {
        const l = self.accept(.label) orelse return null;
        if (try self.peekTerminator()) {
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

        if (self.accept(.equals)) |eq| {
            const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
            return Stmt.initEnds(.{ .let = .{
                .kw = false,
                .lhs = l,
                .tok_eq = eq,
                .rhs = rhs,
            } }, l.range, rhs.range);
        }

        if (self.eoi())
            return Error.UnexpectedEnd;

        return Error.UnexpectedToken;
    }

    fn acceptStmtLet(self: *Self) !?Stmt {
        const k = self.accept(.kw_let) orelse return null;
        const lhs = try self.expect(.label);
        const eq = try self.expect(.equals);
        const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
        return Stmt.initEnds(.{ .let = .{
            .kw = true,
            .lhs = lhs,
            .tok_eq = eq,
            .rhs = rhs,
        } }, k.range, rhs.range);
    }

    fn acceptStmtIf(self: *Self) !?Stmt {
        const k = self.accept(.kw_if) orelse return null;
        const cond = try self.acceptCond() orelse return Error.UnexpectedToken;
        errdefer cond.deinit(self.allocator);
        const tok_then = try self.expect(.kw_then);
        if (try self.peekTerminator()) {
            return Stmt.initEnds(.{ .@"if" = .{
                .cond = cond,
                .tok_then = tok_then,
            } }, k.range, cond.range);
        }
        const st = try self.parseOne() orelse return Error.UnexpectedEnd;
        errdefer st.deinit(self.allocator);
        const stmt_t = try self.allocator.create(Stmt);
        errdefer self.allocator.destroy(stmt_t);
        stmt_t.* = st;

        if (self.accept(.kw_else)) |tok_else| {
            const sf = try self.parseOne() orelse return Error.UnexpectedEnd;
            errdefer sf.deinit(self.allocator);
            const stmt_f = try self.allocator.create(Stmt);
            errdefer self.allocator.destroy(stmt_f);
            stmt_f.* = sf;

            return Stmt.initEnds(.{ .if2 = .{
                .cond = cond,
                .tok_then = tok_then,
                .stmt_t = stmt_t,
                .tok_else = tok_else,
                .stmt_f = stmt_f,
            } }, k.range, stmt_f.range);
        }

        return Stmt.initEnds(.{ .if1 = .{
            .cond = cond,
            .tok_then = tok_then,
            .stmt_t = stmt_t,
        } }, k.range, stmt_t.range);
    }

    fn acceptStmtFor(self: *Self) !?Stmt {
        const k = self.accept(.kw_for) orelse return null;
        const lv = try self.expect(.label);
        const tok_eq = try self.expect(.equals);
        const from = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer from.deinit(self.allocator);
        const tok_to = try self.expect(.kw_to);
        const to = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer to.deinit(self.allocator);

        if (self.accept(.kw_step)) |tok_step| {
            const step = try self.acceptExpr() orelse return Error.UnexpectedToken;
            return Stmt.initEnds(.{ .forstep = .{
                .lv = lv,
                .tok_eq = tok_eq,
                .from = from,
                .tok_to = tok_to,
                .to = to,
                .tok_step = tok_step,
                .step = step,
            } }, k.range, step.range);
        }

        return Stmt.initEnds(.{ .@"for" = .{
            .lv = lv,
            .tok_eq = tok_eq,
            .from = from,
            .tok_to = tok_to,
            .to = to,
        } }, k.range, to.range);
    }

    fn acceptStmtNext(self: *Self) !?Stmt {
        const k = self.accept(.kw_next) orelse return null;
        const lv = try self.expect(.label);

        return Stmt.initEnds(.{ .next = lv }, k.range, lv.range);
    }

    fn acceptStmtGoto(self: *Self) !?Stmt {
        const k = self.accept(.kw_goto) orelse return null;
        const l = try self.expect(.label);

        return Stmt.initEnds(.{ .goto = l }, k.range, l.range);
    }

    fn acceptStmtEnd(self: *Self) !?Stmt {
        const k = self.accept(.kw_end) orelse return null;
        if (self.accept(.kw_if)) |k2| {
            _ = try self.expect(.linefeed);
            return Stmt.initEnds(.endif, k.range, k2.range);
        }
        if (!try self.peekTerminator())
            return Error.ExpectedTerminator;
        return Stmt.init(.end, k.range);
    }

    fn parseOne(self: *Self) (Error || Allocator.Error)!?Stmt {
        if (self.eoi())
            return null;

        // TODO: our terminator behaviour is (still) not very rigorous. Consider
        // "FOR I = 1 to 10 PRINT "X" NEXT I". This probably just parses --
        // should it?

        if (self.accept(.linefeed) != null)
            return self.parseOne();

        if (self.accept(.remark)) |r| {
            try self.append(Stmt.init(.{ .remark = r.payload }, r.range));
            return self.parseOne();
        }

        if (self.accept(.jumplabel)) |l|
            return Stmt.init(.{ .jumplabel = l.payload }, l.range);

        if (try self.acceptStmtLabel()) |s| return s;
        if (try self.acceptStmtLet()) |s| return s;
        if (try self.acceptStmtIf()) |s| return s;
        if (try self.acceptStmtFor()) |s| return s;
        if (try self.acceptStmtNext()) |s| return s;
        if (try self.acceptStmtGoto()) |s| return s;
        if (try self.acceptStmtEnd()) |s| return s;

        return Error.UnexpectedToken;
    }

    fn parseAll(self: *Self) ![]Stmt {
        while (try self.parseOne()) |s| {
            {
                errdefer s.deinit(self.allocator);
                try self.append(s);
            }
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

    return p.parseAll() catch |err| {
        if (err == Allocator.Error.OutOfMemory)
            return err;
        if (p.nt()) |t| {
            std.debug.print("last token: {any}\n", .{t});
        } else {
            std.debug.print("reached EOF\n", .{});
        }
        return err;
    };
}

pub fn free(allocator: Allocator, sx: []Stmt) void {
    for (sx) |s| s.deinit(allocator);
    allocator.free(sx);
}

test "parses a nullary statement" {
    const sx = try parse(testing.allocator, "PRINT\n");
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{
        Stmt.initRange(.{ .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        } }, .{ 1, 1 }, .{ 1, 5 }),
    });
}

test "parses a unary statement" {
    const sx = try parse(testing.allocator, "\n PRINT 42\n");
    defer free(testing.allocator, sx);

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
    defer free(testing.allocator, sx);

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
