const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");
const token = @import("token.zig");
const WithRange = token.WithRange;

const Printer = struct {
    const Self = @This();

    // TODO: wrap writer with another Writer that does the row/col tracking for us.
    writer: std.ArrayList(u8).Writer,
    row: usize = 1,
    col: usize = 1,

    fn advance(self: *Self, r: token.Range) !void {
        while (self.row < r.start.row) {
            self.row += 1;
            self.col = 1;
            try self.writer.writeByte('\n');
        }

        while (self.col < r.start.col) {
            self.col += 1;
            try self.writer.writeByte(' ');
        }
    }

    fn printLit(self: *Self, lit: []const u8) !void {
        for (lit) |c| {
            if (c == '\n') {
                self.row += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
        }
        try self.writer.writeAll(lit);
    }

    fn printExpr(self: *Self, e: parse.Expr) !void {
        try self.advance(e.range);
        switch (e.payload) {
            .imm_number => |n| {
                try std.fmt.format(self.writer, "{d}", .{n});
                self.col += std.fmt.count("{d}", .{n});
            },
            .imm_string => |s| try self.printLit(s),
            .label => |l| try self.printLit(l),
            .binop => |b| {
                try self.printExpr(b.lhs.*);
                switch (b.op) {
                    .mul => try self.printLit(" * "),
                    .div => try self.printLit(" / "),
                    .add => try self.printLit(" + "),
                    .sub => try self.printLit(" - "),
                    .eq => try self.printLit(" = "),
                    .neq => try self.printLit(" <> "),
                    .lt => try self.printLit(" < "),
                    .gt => try self.printLit(" > "),
                    .lte => try self.printLit(" <= "),
                    .gte => try self.printLit(" >= "),
                    .@"and" => try self.printLit(" AND "),
                    .@"or" => try self.printLit(" OR "),
                    .xor => try self.printLit(" XOR "),
                }
                try self.printExpr(b.rhs.*);
            },
        }
    }

    fn printStmt(self: *Self, s: parse.Stmt) !void {
        try self.advance(s.range);
        switch (s.payload) {
            .remark => |r| {
                try std.fmt.format(self.writer, "'{s}\n", .{r});
                self.row += 1;
                self.col = 1;
            },
            .call => |c| {
                try self.printLit(c.name.payload);
                for (c.args, 0..) |e, i| {
                    try self.printLit(if (i == 0) " " else ", ");
                    try self.printExpr(e);
                }
                try self.printLit("\n");
            },
            .let => |l| {
                if (l.kw) try self.printLit("LET ");
                try std.fmt.format(self.writer, "{s} = ", .{l.lhs.payload});
                self.col += l.lhs.payload.len + 3;
                try self.printExpr(l.rhs);
                try self.printLit("\n");
            },
            .@"if" => |i| {
                try self.printLit("IF ");
                try self.printExpr(i.cond);
                try self.printLit(" THEN\n");
            },
            .if1 => |i| {
                try self.printLit("IF ");
                try self.printExpr(i.cond);
                try self.printLit(" THEN ");
                try self.printStmt(i.stmt.*);
            },
            .end => {
                try self.printLit("END\n");
            },
            .endif => {
                try self.printLit("END IF\n");
            },
        }
    }

    fn print(self: *Self, sx: []parse.Stmt) !void {
        for (sx) |s|
            try self.printStmt(s);
    }
};

pub fn print(allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    const writer = out.writer();

    var p = Printer{ .writer = writer };
    try p.print(sx);

    return out.toOwnedSlice();
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
