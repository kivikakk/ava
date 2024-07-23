const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");
const token = @import("token.zig");
const WithRange = token.WithRange;

fn printExpr(writer: std.ArrayList(u8).Writer, e: parse.Expr) !void {
    switch (e) {
        .imm_number => |n| try std.fmt.format(writer, "{d}", .{n}),
        .imm_string => |s| try writer.writeAll(s),
        .label => |l| try writer.writeAll(l),
        .binop => |b| {
            try printExpr(writer, b.lhs.payload);
            switch (b.op) {
                .mul => try writer.writeAll(" * "),
                .div => try writer.writeAll(" / "),
                .add => try writer.writeAll(" + "),
                .sub => try writer.writeAll(" - "),
            }
            try printExpr(writer, b.rhs.payload);
        },
    }
}

const Printer = struct {
    const Self = @This();

    row: usize = 1,
    col: usize = 1,

    fn advance(self: *Self, writer: std.ArrayList(u8).Writer, r: token.Range) !void {
        while (self.row < r.start.row) {
            self.row += 1;
            self.col = 1;
            try writer.writeByte('\n');
        }

        while (self.col < r.start.col) {
            self.col += 1;
            try writer.writeByte(' ');
        }
    }

    fn print(self: *Self, allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
        var out = std.ArrayList(u8).init(allocator);
        defer out.deinit();

        const writer = out.writer();

        for (sx) |s| {
            switch (s) {
                .remark => |r| {
                    try self.advance(writer, r.range);
                    try std.fmt.format(writer, "'{s}\n", .{r.payload});
                    self.row += 1;
                    self.col = 1;
                },
                .call => |c| {
                    try self.advance(writer, c.name.range);
                    try writer.writeAll(c.name.payload);
                    for (c.args, 0..) |e, i| {
                        try writer.writeAll(if (i == 0) " " else ", ");
                        try printExpr(writer, e.payload);
                    }
                    try writer.writeByte('\n');
                    self.row += 1;
                    self.col = 1;
                },
                .let => |l| {
                    try self.advance(writer, if (l.kw) |kw| kw.range else l.lhs.range);
                    if (l.kw != null) try writer.writeAll("LET ");
                    try std.fmt.format(writer, "{s} = ", .{l.lhs.payload});
                    try printExpr(writer, l.rhs.payload);
                    try writer.writeByte('\n');
                    self.row += 1;
                    self.col = 1;
                },
                .@"if" => |i| {
                    try self.advance(writer, i.kw.range);
                    try writer.writeAll("IF ");
                    try printExpr(writer, i.cond.payload);
                    try writer.writeAll(" THEN\n");
                    self.row += 1;
                    self.col = 1;
                },
                .end => |k| {
                    try self.advance(writer, k.range);
                    try writer.writeAll("END\n");
                    self.row += 1;
                    self.col = 1;
                },
                .endif => |k| {
                    try self.advance(writer, k.range);
                    try writer.writeAll("END IF\n");
                    self.row += 1;
                    self.col = 1;
                },
            }
        }

        return out.toOwnedSlice();
    }
};

pub fn print(allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
    var p = Printer{};
    return try p.print(allocator, sx);
}

test "testpp/01.bas" {
    const inp = try std.fs.cwd().readFileAlloc(testing.allocator, "src/testpp/01.bas", 1048576);
    defer testing.allocator.free(inp);

    const sx = try parse.parse(testing.allocator, inp);
    defer parse.freeStmts(testing.allocator, sx);

    const out = try print(testing.allocator, sx);
    defer testing.allocator.free(out);

    try testing.expectEqualStrings(inp, out);
}
