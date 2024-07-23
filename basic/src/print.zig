const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");
const WithRange = @import("token.zig").WithRange;

fn printExpr(writer: std.ArrayList(u8).Writer, e: WithRange(parse.Expr)) !void {
    switch (e.payload) {
        .imm_number => |n| try std.fmt.format(writer, "{d}", .{n}),
        .imm_string => |s| try writer.writeAll(s),
        .label => |l| try writer.writeAll(l),
    }
}

pub fn print(allocator: Allocator, sx: []parse.Stmt) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    const writer = out.writer();

    for (sx) |s| {
        switch (s) {
            .remark => |r| {
                try std.fmt.format(writer, "'{s}\n", .{r.payload});
            },
            .call => |c| {
                try writer.writeAll(c.name.payload);
                for (c.args, 0..) |e, i| {
                    try writer.writeAll(if (i == 0) " " else ", ");
                    try printExpr(writer, e);
                }
                try writer.writeByte('\n');
            },
            .let => |l| {
                if (l.kw != null) try writer.writeAll("LET ");
                try std.fmt.format(writer, "{s} = ", .{l.lhs.payload});
                try printExpr(writer, l.rhs);
                try writer.writeByte('\n');
            },
        }
    }

    return out.toOwnedSlice();
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
