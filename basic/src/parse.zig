const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");
const ast = @import("ast.zig");
const loc = @import("loc.zig");
const Loc = loc.Loc;
const Range = loc.Range;
const WithRange = loc.WithRange;

pub const Error = error{
    ExpectedTerminator,
    UnexpectedToken,
    UnexpectedEnd,
};

const State = union(enum) {
    init,
    call: struct {
        label: WithRange([]const u8),
        args: std.ArrayList(ast.Expr),
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
    tx: []Token,
    nti: usize = 0,
    sx: std.ArrayListUnmanaged(ast.Stmt) = .{},
    pending_rem: ?ast.Stmt = null,
    errorloc: ?*Loc,

    fn init(allocator: Allocator, inp: []const u8, errorloc: ?*Loc) !Self {
        const tx = try Tokenizer.tokenize(allocator, inp, errorloc);
        return .{
            .allocator = allocator,
            .tx = tx,
            .errorloc = errorloc,
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

    fn append(self: *Self, s: ast.Stmt) !void {
        try self.sx.append(self.allocator, s);
    }

    fn eoi(self: *const Self) bool {
        return self.nti == self.tx.len;
    }

    fn nt(self: *const Self) ?Token {
        if (self.eoi())
            return null;
        return self.tx[self.nti];
    }

    fn accept(self: *Self, comptime tt: Token.Tag) ?WithRange(std.meta.TagPayload(Token.Payload, tt)) {
        const t = self.nt() orelse return null;
        if (t.payload == tt) {
            self.nti += 1;
            const payload = @field(t.payload, @tagName(tt));
            return WithRange(std.meta.TagPayload(Token.Payload, tt))
                .init(payload, t.range);
        }
        return null;
    }

    fn expect(self: *Self, comptime tt: Token.Tag) !WithRange(std.meta.TagPayload(Token.Payload, tt)) {
        return self.accept(tt) orelse Error.UnexpectedToken;
    }

    fn peek(self: *Self, comptime tt: Token.Tag) bool {
        const t = self.nt() orelse return false;
        return t.payload == tt;
    }

    fn peekTerminator(self: *Self) !bool {
        if (self.eoi())
            return true; // XXX ?

        if (self.accept(.remark)) |r| {
            std.debug.assert(self.pending_rem == null);
            self.pending_rem = ast.Stmt.init(.{ .remark = r.payload }, r.range);
        }

        return self.peek(.linefeed) or
            self.peek(.colon) or
            self.peek(.kw_else) or
            self.peek(.parenc);
    }

    fn acceptFactor(self: *Self) !?ast.Expr {
        if (self.accept(.number)) |n|
            return ast.Expr.init(.{ .imm_number = n.payload }, n.range);

        if (self.accept(.label)) |l|
            return ast.Expr.init(.{ .label = l.payload }, l.range);

        if (self.accept(.string)) |s|
            return ast.Expr.init(.{ .imm_string = s.payload }, s.range);

        if (self.accept(.minus)) |m| {
            const e = try self.acceptExpr() orelse return Error.UnexpectedToken;
            errdefer e.deinit(self.allocator);

            const expr = try self.allocator.create(ast.Expr);
            expr.* = e;
            return ast.Expr.init(.{ .negate = expr }, Range.initEnds(m.range, e.range));
        }

        if (self.accept(.pareno)) |p| {
            const e = try self.acceptExpr() orelse return Error.UnexpectedToken;
            errdefer e.deinit(self.allocator);
            const tok_pc = try self.expect(.parenc);

            const expr = try self.allocator.create(ast.Expr);
            expr.* = e;
            return ast.Expr.init(.{ .paren = expr }, Range.initEnds(p.range, tok_pc.range));
        }

        return null;
    }

    // TODO: comptime wonk to define accept(Term,ast.Expr,Cond) in common?
    fn acceptTerm(self: *Self) !?ast.Expr {
        const f = try self.acceptFactor() orelse return null;
        errdefer f.deinit(self.allocator);
        const op = op: {
            if (self.accept(.asterisk)) |o|
                break :op WithRange(ast.Op).init(.mul, o.range)
            else if (self.accept(.fslash)) |o|
                break :op WithRange(ast.Op).init(.div, o.range);
            return f;
        };
        const f2 = try self.acceptFactor() orelse return Error.UnexpectedToken;
        errdefer f2.deinit(self.allocator);

        const lhs = try self.allocator.create(ast.Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = f;
        const rhs = try self.allocator.create(ast.Expr);
        rhs.* = f2;

        return ast.Expr.init(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, Range.initEnds(f.range, f2.range));
    }

    fn acceptExpr(self: *Self) (Allocator.Error || Error)!?ast.Expr {
        const t = try self.acceptTerm() orelse return null;
        errdefer t.deinit(self.allocator);
        const op = op: {
            if (self.accept(.plus)) |o|
                break :op WithRange(ast.Op).init(.add, o.range)
            else if (self.accept(.minus)) |o|
                break :op WithRange(ast.Op).init(.sub, o.range);
            return t;
        };
        const t2 = try self.acceptTerm() orelse return Error.UnexpectedToken;
        errdefer t2.deinit(self.allocator);

        const lhs = try self.allocator.create(ast.Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = t;
        const rhs = try self.allocator.create(ast.Expr);
        rhs.* = t2;

        return ast.Expr.init(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, Range.initEnds(t.range, t2.range));
    }

    fn acceptCond(self: *Self) !?ast.Expr {
        const e = try self.acceptExpr() orelse return null;
        errdefer e.deinit(self.allocator);
        const op = op: {
            if (self.accept(.equals)) |o|
                break :op WithRange(ast.Op).init(.eq, o.range)
            else if (self.accept(.diamond)) |o|
                break :op WithRange(ast.Op).init(.neq, o.range)
            else if (self.accept(.angleo)) |o|
                break :op WithRange(ast.Op).init(.lt, o.range)
            else if (self.accept(.anglec)) |o|
                break :op WithRange(ast.Op).init(.gt, o.range)
            else if (self.accept(.lte)) |o|
                break :op WithRange(ast.Op).init(.lte, o.range)
            else if (self.accept(.gte)) |o|
                break :op WithRange(ast.Op).init(.gte, o.range);
            return e;
        };
        const e2 = try self.acceptExpr() orelse return Error.UnexpectedToken;
        errdefer e2.deinit(self.allocator);

        const lhs = try self.allocator.create(ast.Expr);
        errdefer self.allocator.destroy(lhs);
        lhs.* = e;
        const rhs = try self.allocator.create(ast.Expr);
        rhs.* = e2;

        return ast.Expr.init(.{ .binop = .{
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
        } }, Range.initEnds(e.range, e2.range));
    }

    fn acceptExprList(self: *Self, comptime septoks: []const Token.Tag, separators: ?*std.ArrayListUnmanaged(Token), trailing: bool) !?[]ast.Expr {
        var ex = std.ArrayList(ast.Expr).init(self.allocator);
        errdefer {
            for (ex.items) |i| i.deinit(self.allocator);
            ex.deinit();
        }

        {
            const e = try self.acceptExpr() orelse return null;
            errdefer e.deinit(self.allocator);
            try ex.append(e);
        }

        while (true) {
            // PRINT a
            // PRINT a; b
            // XYZ a, b, c
            var found = false;
            inline for (septoks) |st| {
                if (self.accept(st)) |t| {
                    if (separators) |so|
                        try so.append(self.allocator, Token.init(st, t.range));
                    found = true;
                    break;
                }
            }
            if (!found) {
                // No separator found.
                if (!try self.peekTerminator())
                    return Error.ExpectedTerminator;
                break;
            }

            // PRINT a,
            // PRINT a; b;
            // XYZ c, d,

            if (trailing and try self.peekTerminator()) {
                // Trailing permitted, and:
                // PRINT a,\n
                // PRINT a; b;\n
                // XYZ c, d,\n
                break;
            }

            const e2 = try self.acceptExpr() orelse
                return Error.UnexpectedToken;
            errdefer e2.deinit(self.allocator);
            try ex.append(e2);
        }

        return try ex.toOwnedSlice();
    }

    fn acceptBuiltinPrint(self: *Self, l: WithRange([]const u8)) !?ast.Stmt {
        if (try self.peekTerminator()) {
            return ast.Stmt.init(.{ .print = .{
                .args = &.{},
                .separators = &.{},
            } }, l.range);
        }

        var separators = std.ArrayListUnmanaged(Token){};
        defer separators.deinit(self.allocator);

        const ex = try self.acceptExprList(&.{ .comma, .semicolon }, &separators, true) orelse
            return Error.UnexpectedToken;
        errdefer ast.Expr.deinitAll(self.allocator, ex);

        var seps = try self.allocator.alloc(WithRange(u8), separators.items.len);
        for (separators.items, 0..) |s, i| {
            seps[i] = WithRange(u8).init(switch (s.payload) {
                .comma => ',',
                .semicolon => ';',
                else => unreachable,
            }, s.range);
        }

        return ast.Stmt.init(.{ .print = .{
            .args = ex,
            .separators = seps,
        } }, Range.initEnds(l.range, if (seps.len == ex.len) seps[ex.len - 1].range else ex[ex.len - 1].range));
    }

    fn acceptStmtLabel(self: *Self) !?ast.Stmt {
        const l = self.accept(.label) orelse return null;

        if (std.ascii.eqlIgnoreCase(l.payload, "print"))
            return self.acceptBuiltinPrint(l);

        if (try self.peekTerminator()) {
            return ast.Stmt.init(.{ .call = .{
                .name = l,
                .args = &.{},
            } }, l.range);
        }

        if (try self.acceptExprList(&.{.comma}, null, false)) |ex| {
            return ast.Stmt.init(.{ .call = .{
                .name = l,
                .args = ex,
            } }, Range.initEnds(l.range, ex[ex.len - 1].range));
        }

        if (self.accept(.equals)) |eq| {
            const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
            return ast.Stmt.init(.{ .let = .{
                .kw = false,
                .lhs = l,
                .tok_eq = eq,
                .rhs = rhs,
            } }, Range.initEnds(l.range, rhs.range));
        }

        if (self.eoi())
            return Error.UnexpectedEnd;

        return Error.UnexpectedToken;
    }

    fn acceptStmtLet(self: *Self) !?ast.Stmt {
        const k = self.accept(.kw_let) orelse return null;
        const lhs = try self.expect(.label);
        const eq = try self.expect(.equals);
        const rhs = try self.acceptExpr() orelse return Error.UnexpectedToken;
        return ast.Stmt.init(.{ .let = .{
            .kw = true,
            .lhs = lhs,
            .tok_eq = eq,
            .rhs = rhs,
        } }, Range.initEnds(k.range, rhs.range));
    }

    fn acceptStmtIf(self: *Self) !?ast.Stmt {
        const k = self.accept(.kw_if) orelse return null;
        const cond = try self.acceptCond() orelse return Error.UnexpectedToken;
        errdefer cond.deinit(self.allocator);
        const tok_then = try self.expect(.kw_then);
        if (try self.peekTerminator()) {
            return ast.Stmt.init(.{ .@"if" = .{
                .cond = cond,
                .tok_then = tok_then,
            } }, Range.initEnds(k.range, cond.range));
        }
        const st = try self.parseOne() orelse return Error.UnexpectedEnd;
        errdefer st.deinit(self.allocator);
        const stmt_t = try self.allocator.create(ast.Stmt);
        errdefer self.allocator.destroy(stmt_t);
        stmt_t.* = st;

        if (self.accept(.kw_else)) |tok_else| {
            const sf = try self.parseOne() orelse return Error.UnexpectedEnd;
            errdefer sf.deinit(self.allocator);
            const stmt_f = try self.allocator.create(ast.Stmt);
            errdefer self.allocator.destroy(stmt_f);
            stmt_f.* = sf;

            return ast.Stmt.init(.{ .if2 = .{
                .cond = cond,
                .tok_then = tok_then,
                .stmt_t = stmt_t,
                .tok_else = tok_else,
                .stmt_f = stmt_f,
            } }, Range.initEnds(k.range, stmt_f.range));
        }

        return ast.Stmt.init(.{ .if1 = .{
            .cond = cond,
            .tok_then = tok_then,
            .stmt_t = stmt_t,
        } }, Range.initEnds(k.range, stmt_t.range));
    }

    fn acceptStmtFor(self: *Self) !?ast.Stmt {
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
            return ast.Stmt.init(.{ .forstep = .{
                .lv = lv,
                .tok_eq = tok_eq,
                .from = from,
                .tok_to = tok_to,
                .to = to,
                .tok_step = tok_step,
                .step = step,
            } }, Range.initEnds(k.range, step.range));
        }

        return ast.Stmt.init(.{ .@"for" = .{
            .lv = lv,
            .tok_eq = tok_eq,
            .from = from,
            .tok_to = tok_to,
            .to = to,
        } }, Range.initEnds(k.range, to.range));
    }

    fn acceptStmtNext(self: *Self) !?ast.Stmt {
        const k = self.accept(.kw_next) orelse return null;
        const lv = try self.expect(.label);

        return ast.Stmt.init(.{ .next = lv }, Range.initEnds(k.range, lv.range));
    }

    fn acceptStmtGoto(self: *Self) !?ast.Stmt {
        const k = self.accept(.kw_goto) orelse return null;
        const l = try self.expect(.label);

        return ast.Stmt.init(.{ .goto = l }, Range.initEnds(k.range, l.range));
    }

    fn acceptStmtEnd(self: *Self) !?ast.Stmt {
        const k = self.accept(.kw_end) orelse return null;
        if (self.accept(.kw_if)) |k2| {
            _ = try self.expect(.linefeed);
            return ast.Stmt.init(.endif, Range.initEnds(k.range, k2.range));
        }
        if (!try self.peekTerminator())
            return Error.ExpectedTerminator;
        return ast.Stmt.init(.end, k.range);
    }

    fn parseOne(self: *Self) (Error || Allocator.Error)!?ast.Stmt {
        if (self.eoi())
            return null;

        // TODO: our terminator behaviour is (still) not very rigorous. Consider
        // "FOR I = 1 to 10 PRINT "X" NEXT I". This probably just parses --
        // should it?

        if (self.accept(.linefeed) != null)
            return self.parseOne();

        if (self.accept(.remark)) |r| {
            try self.append(ast.Stmt.init(.{ .remark = r.payload }, r.range));
            return self.parseOne();
        }

        if (self.accept(.jumplabel)) |l|
            return ast.Stmt.init(.{ .jumplabel = l.payload }, l.range);

        if (try self.acceptStmtLabel()) |s| return s;
        if (try self.acceptStmtLet()) |s| return s;
        if (try self.acceptStmtIf()) |s| return s;
        if (try self.acceptStmtFor()) |s| return s;
        if (try self.acceptStmtNext()) |s| return s;
        if (try self.acceptStmtGoto()) |s| return s;
        if (try self.acceptStmtEnd()) |s| return s;

        return Error.UnexpectedToken;
    }

    fn parseAll(self: *Self) ![]ast.Stmt {
        while (self.parseOne() catch |err| {
            if (self.nt()) |t| {
                if (self.errorloc) |el|
                    el.* = t.range.start;
            }
            return err;
        }) |s| {
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

pub fn parse(allocator: Allocator, inp: []const u8, errorloc: ?*Loc) ![]ast.Stmt {
    var p = try Parser.init(allocator, inp, errorloc);
    defer p.deinit();

    return try p.parseAll();
}

pub fn free(allocator: Allocator, sx: []ast.Stmt) void {
    for (sx) |s| s.deinit(allocator);
    allocator.free(sx);
}

test "parses a nullary call" {
    const sx = try parse(testing.allocator, "NYONK\n", null);
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(&[_]ast.Stmt{
        ast.Stmt.init(.{ .call = .{
            .name = WithRange([]const u8).init("NYONK", Range.init(.{ 1, 1 }, .{ 1, 5 })),
            .args = &.{},
        } }, Range.init(.{ 1, 1 }, .{ 1, 5 })),
    }, sx);
}

test "parses a unary statement" {
    const sx = try parse(testing.allocator, "\n NYONK 42\n", null);
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(&[_]ast.Stmt{
        ast.Stmt.init(.{ .call = .{
            .name = WithRange([]const u8).init("NYONK", Range.init(.{ 2, 2 }, .{ 2, 6 })),
            .args = &.{
                ast.Expr.init(.{ .imm_number = 42 }, Range.init(.{ 2, 8 }, .{ 2, 9 })),
            },
        } }, Range.init(.{ 2, 2 }, .{ 2, 9 })),
    }, sx);
}

test "parses a binary statement" {
    const sx = try parse(testing.allocator, "NYONK X$, Y%\n", null);
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(&[_]ast.Stmt{
        ast.Stmt.init(.{ .call = .{
            .name = WithRange([]const u8).init("NYONK", Range.init(.{ 1, 1 }, .{ 1, 5 })),
            .args = &.{
                ast.Expr.init(.{ .label = "X$" }, Range.init(.{ 1, 7 }, .{ 1, 8 })),
                ast.Expr.init(.{ .label = "Y%" }, Range.init(.{ 1, 11 }, .{ 1, 12 })),
            },
        } }, Range.init(.{ 1, 1 }, .{ 1, 12 })),
    }, sx);
}

test "parses a PRINT statement with semicolons" {
    const sx = try parse(testing.allocator, "PRINT X$, Y%; Z&\n", null);
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(&[_]ast.Stmt{
        ast.Stmt.init(.{ .print = .{
            .args = &.{
                ast.Expr.init(.{ .label = "X$" }, Range.init(.{ 1, 7 }, .{ 1, 8 })),
                ast.Expr.init(.{ .label = "Y%" }, Range.init(.{ 1, 11 }, .{ 1, 12 })),
                ast.Expr.init(.{ .label = "Z&" }, Range.init(.{ 1, 15 }, .{ 1, 16 })),
            },
            .separators = &.{
                WithRange(u8).init(',', Range.init(.{ 1, 9 }, .{ 1, 9 })),
                WithRange(u8).init(';', Range.init(.{ 1, 13 }, .{ 1, 13 })),
            },
        } }, Range.init(.{ 1, 1 }, .{ 1, 16 })),
    }, sx);
}

test "parses a PRINT statement with trailing separator" {
    const sx = try parse(testing.allocator, "PRINT X$, Y%; Z&,\n", null);
    defer free(testing.allocator, sx);

    try testing.expectEqualDeep(&[_]ast.Stmt{
        ast.Stmt.init(.{ .print = .{
            .args = &.{
                ast.Expr.init(.{ .label = "X$" }, Range.init(.{ 1, 7 }, .{ 1, 8 })),
                ast.Expr.init(.{ .label = "Y%" }, Range.init(.{ 1, 11 }, .{ 1, 12 })),
                ast.Expr.init(.{ .label = "Z&" }, Range.init(.{ 1, 15 }, .{ 1, 16 })),
            },
            .separators = &.{
                WithRange(u8).init(',', Range.init(.{ 1, 9 }, .{ 1, 9 })),
                WithRange(u8).init(';', Range.init(.{ 1, 13 }, .{ 1, 13 })),
                WithRange(u8).init(',', Range.init(.{ 1, 17 }, .{ 1, 17 })),
            },
        } }, Range.init(.{ 1, 1 }, .{ 1, 17 })),
    }, sx);
}

test "parse error" {
    var errorloc: Loc = .{};
    const eu = parse(testing.allocator, "1", &errorloc);
    try testing.expectError(error.UnexpectedToken, eu);
    try testing.expectEqual(Loc{ .row = 1, .col = 1 }, errorloc);
}
