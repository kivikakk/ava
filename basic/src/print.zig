const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Expr = @import("ast/Expr.zig");
const Stmt = @import("ast/Stmt.zig");
const Parser = @import("Parser.zig");
const loc = @import("loc.zig");
const Loc = loc.Loc;
const @"test" = @import("test.zig");

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
            .buf = .{},
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

    fn advanceLoc(self: *Self, l: Loc) !void {
        while (self.row < l.row)
            try self.writer.writeByte('\n');

        while (self.col < l.col)
            try self.writer.writeByte(' ');
    }

    fn advance(self: *Self, r: loc.Range) !void {
        try self.advanceLoc(r.start);
    }

    fn printExpr(self: *Self, e: Expr) !void {
        try self.advance(e.range);
        switch (e.payload) {
            .imm_integer => |n| try std.fmt.format(self.writer, "{d}", .{n}),
            .imm_long => |n| try std.fmt.format(self.writer, "{d}", .{n}),
            .imm_single => |n| try std.fmt.format(self.writer, "{d}", .{n}),
            .imm_double => |n| try std.fmt.format(self.writer, "{d}", .{n}),
            .imm_string => |s| try std.fmt.format(self.writer, "\"{s}\"", .{s}),
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
            .paren => |p| {
                try self.writer.writeByte('(');
                try self.printExpr(p.*);
                try self.advanceLoc(p.range.end.back());
                try self.writer.writeByte(')');
            },
            .negate => |m| {
                try self.writer.writeByte('-');
                try self.printExpr(m.*);
            },
        }
    }

    fn printStmt(self: *Self, s: Stmt) !void {
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
            .print => |p| {
                try self.writer.writeAll("PRINT");
                for (p.args, 0..) |e, i| {
                    if (i > 0) {
                        try self.advance(p.separators[i - 1].range);
                        try self.writer.writeByte(p.separators[i - 1].payload);
                    }
                    try self.printExpr(e);
                }
                if (p.separators.len == p.args.len) {
                    try self.advance(p.separators[p.args.len - 1].range);
                    try self.writer.writeByte(p.separators[p.args.len - 1].payload);
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
            .pragma_printed => |p| {
                try self.writer.writeAll("PRAGMA PRINTED ");
                try self.advance(p.range);
                try std.fmt.format(self.writer, "\"{s}\"", .{p.payload});
            },
        }
    }

    fn print(self: *Self, sx: []Stmt) ![]const u8 {
        for (sx) |s|
            try self.printStmt(s);
        try self.buf.append(self.allocator, '\n');
        return self.buf.toOwnedSlice(self.allocator);
    }
};

pub fn print(allocator: Allocator, sx: []Stmt) ![]const u8 {
    var p = try Printer.init(allocator);
    defer p.deinit();

    return p.print(sx);
}

fn expectPpRoundtrip(allocator: Allocator, path: []const u8, contents: []const u8) !void {
    _ = path;

    const sx = try Parser.parse(allocator, contents, null);
    defer Parser.free(allocator, sx);

    const out = try print(allocator, sx);
    defer allocator.free(out);

    try testing.expectEqualStrings(contents, out);
}

test "roundtrips" {
    const matches = try @"test".matchingBasPaths("pprt.");
    defer matches.deinit();

    for (matches.entries) |e|
        try testing.checkAllAllocationFailures(
            testing.allocator,
            expectPpRoundtrip,
            .{ e.path, e.contents },
        );
}
