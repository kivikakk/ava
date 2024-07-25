const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");
const token = @import("token.zig");
const WithRange = token.WithRange;

const Printer = struct {
    const Self = @This();
    const Writer = std.io.GenericWriter(*Self, Allocator.Error, writerFn);

    allocator: Allocator,
    buf: std.ArrayListUnmanaged(u8),
    writer: Writer,

    row: usize = 1,
    col: usize = 1,

    fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .buf = std.ArrayListUnmanaged(u8){},
            .writer = Writer{ .context = self },
        };
        return self;
    }

    fn deinit(self: *Self) void {
        self.buf.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn writerFn(self: *Self, m: []const u8) Allocator.Error!usize {
        for (m) |c| {
            if (c == '\n') {
                self.row += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
        }
        try self.buf.appendSlice(self.allocator, m);
        return m.len;
    }

    fn advance(self: *Self, r: token.Range) !void {
        while (self.row < r.start.row)
            try self.writer.writeByte('\n');

        while (self.col < r.start.col)
            try self.writer.writeByte(' ');
    }

    fn printExpr(self: *Self, e: parse.Expr) !void {
        try self.advance(e.range);
        switch (e.payload) {
            .imm_number => |n| try std.fmt.format(self.writer, "{d}", .{n}),
            .imm_string => |s| try self.writer.writeAll(s),
            .label => |l| try self.writer.writeAll(l),
            .binop => |b| {
                try self.printExpr(b.lhs.*);
                try self.advance(b.op.range);
                switch (b.op.payload) {
                    .mul => try self.writer.writeAll("*"),
                    .div => try self.writer.writeAll("/"),
                    .add => try self.writer.writeAll("+"),
                    .sub => try self.writer.writeAll("-"),
                    .eq => try self.writer.writeAll("="),
                    .neq => try self.writer.writeAll("<>"),
                    .lt => try self.writer.writeAll("<"),
                    .gt => try self.writer.writeAll(">"),
                    .lte => try self.writer.writeAll("<="),
                    .gte => try self.writer.writeAll(">="),
                    .@"and" => try self.writer.writeAll("AND"),
                    .@"or" => try self.writer.writeAll("OR"),
                    .xor => try self.writer.writeAll("XOR"),
                }
                try self.printExpr(b.rhs.*);
            },
        }
    }

    fn printStmt(self: *Self, s: parse.Stmt) !void {
        try self.advance(s.range);
        switch (s.payload) {
            .remark => |r| try self.writer.writeAll(r),
            .call => |c| {
                try self.writer.writeAll(c.name.payload);
                for (c.args, 0..) |e, i| {
                    if (i > 0)
                        try self.writer.writeByte(',');
                    try self.printExpr(e);
                }
            },
            .let => |l| {
                if (l.kw) try self.writer.writeAll("LET");
                try self.advance(l.lhs.range);
                try self.writer.writeAll(l.lhs.payload);
                try self.advance(l.tok_eq.range);
                try self.writer.writeByte('=');
                try self.printExpr(l.rhs);
            },
            .@"if" => |i| {
                try self.writer.writeAll("IF");
                try self.printExpr(i.cond);
                try self.advance(i.tok_then.range);
                try self.writer.writeAll("THEN");
            },
            .if1 => |i| {
                try self.writer.writeAll("IF");
                try self.printExpr(i.cond);
                try self.advance(i.tok_then.range);
                try self.writer.writeAll("THEN");
                try self.printStmt(i.stmt_t.*);
            },
            .if2 => |i| {
                try self.writer.writeAll("IF");
                try self.printExpr(i.cond);
                try self.advance(i.tok_then.range);
                try self.writer.writeAll("THEN");
                try self.printStmt(i.stmt_t.*);
                try self.advance(i.tok_else.range);
                try self.writer.writeAll("ELSE");
                try self.printStmt(i.stmt_f.*);
            },
            .@"for" => |f| {
                try self.writer.writeAll("FOR");
                try self.advance(f.lv.range);
                try self.writer.writeAll(f.lv.payload);
                try self.advance(f.tok_eq.range);
                try self.writer.writeByte('=');
                try self.printExpr(f.from);
                try self.advance(f.tok_to.range);
                try self.writer.writeAll("TO");
                try self.printExpr(f.to);
            },
            .forstep => |f| {
                try self.writer.writeAll("FOR");
                try self.advance(f.lv.range);
                try self.writer.writeAll(f.lv.payload);
                try self.advance(f.tok_eq.range);
                try self.writer.writeByte('=');
                try self.printExpr(f.from);
                try self.advance(f.tok_to.range);
                try self.writer.writeAll("TO");
                try self.printExpr(f.to);
                try self.advance(f.tok_step.range);
                try self.writer.writeAll("STEP");
                try self.printExpr(f.step);
            },
            .next => |lv| {
                try self.writer.writeAll("NEXT");
                try self.advance(lv.range);
                try self.writer.writeAll(lv.payload);
            },
            .jumplabel => |l| try self.writer.writeAll(l),
            .goto => |l| {
                try self.writer.writeAll("GOTO");
                try self.advance(l.range);
                try self.writer.writeAll(l.payload);
            },
            .end => try self.writer.writeAll("END"),
            .endif => try self.writer.writeAll("END IF"),
        }
    }

    fn print(self: *Self, sx: []parse.Stmt) ![]const u8 {
        for (sx) |s|
            try self.printStmt(s);
        try self.buf.append(self.allocator, '\n');
        return self.buf.toOwnedSlice(self.allocator);
    }
};

pub fn print(allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
    var p = try Printer.init(allocator);
    defer p.deinit();

    return p.print(sx);
}

fn testppInner(allocator: Allocator, inp: []const u8) !void {
    const sx = try parse.parse(allocator, inp);
    defer parse.freeStmts(allocator, sx);

    const out = try print(allocator, sx);
    defer allocator.free(out);

    try testing.expectEqualStrings(inp, out);
}

fn testpp(comptime path: []const u8) !void {
    const inp = @embedFile("testpp/" ++ path);

    try testing.checkAllAllocationFailures(testing.allocator, testppInner, .{inp});
}

test "testpp" {
    try testpp("01.bas");
    try testpp("02.bas");
}
