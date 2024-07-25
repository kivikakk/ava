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
                switch (b.op) {
                    .mul => try self.writer.writeAll(" * "),
                    .div => try self.writer.writeAll(" / "),
                    .add => try self.writer.writeAll(" + "),
                    .sub => try self.writer.writeAll(" - "),
                    .eq => try self.writer.writeAll(" = "),
                    .neq => try self.writer.writeAll(" <> "),
                    .lt => try self.writer.writeAll(" < "),
                    .gt => try self.writer.writeAll(" > "),
                    .lte => try self.writer.writeAll(" <= "),
                    .gte => try self.writer.writeAll(" >= "),
                    .@"and" => try self.writer.writeAll(" AND "),
                    .@"or" => try self.writer.writeAll(" OR "),
                    .xor => try self.writer.writeAll(" XOR "),
                }
                try self.printExpr(b.rhs.*);
            },
        }
    }

    fn printStmt(self: *Self, s: parse.Stmt) !void {
        try self.advance(s.range);
        switch (s.payload) {
            .remark => |r| try std.fmt.format(self.writer, "'{s}\n", .{r}),
            .call => |c| {
                try self.writer.writeAll(c.name.payload);
                for (c.args, 0..) |e, i| {
                    try self.writer.writeAll(if (i == 0) " " else ", ");
                    try self.printExpr(e);
                }
                try self.writer.writeAll("\n");
            },
            .let => |l| {
                if (l.kw) try self.writer.writeAll("LET ");
                try std.fmt.format(self.writer, "{s} = ", .{l.lhs.payload});
                try self.printExpr(l.rhs);
                try self.writer.writeAll("\n");
            },
            .@"if" => |i| {
                try self.writer.writeAll("IF ");
                try self.printExpr(i.cond);
                try self.writer.writeAll(" THEN\n");
            },
            .if1 => |i| {
                try self.writer.writeAll("IF ");
                try self.printExpr(i.cond);
                try self.writer.writeAll(" THEN ");
                try self.printStmt(i.stmt.*);
            },
            .end => try self.writer.writeAll("END\n"),
            .endif => try self.writer.writeAll("END IF\n"),
        }
    }

    fn print(self: *Self, sx: []parse.Stmt) ![]const u8 {
        for (sx) |s|
            try self.printStmt(s);
        return self.buf.toOwnedSlice(self.allocator);
    }
};

pub fn print(allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
    var p = try Printer.init(allocator);
    defer p.deinit();

    return try p.print(sx);
}

fn testpp(comptime path: []const u8) !void {
    const inp = @embedFile("testpp/" ++ path);

    const sx = try parse.parse(testing.allocator, inp);
    defer parse.freeStmts(testing.allocator, sx);

    const out = try print(testing.allocator, sx);
    defer testing.allocator.free(out);

    try testing.expectEqualStrings(inp, out);
}

test "testpp" {
    try testpp("01.bas");
}
