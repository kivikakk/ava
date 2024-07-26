const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");

const Compiler = struct {
    const Self = @This();

    allocator: Allocator,
    buf: std.ArrayListUnmanaged(u8) = .{},

    fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Self) void {
        self.buf.deinit(self.allocator);
    }

    fn compile(self: *Self, sx: []parse.Stmt) ![]const u8 {
        for (sx) |s| {
            switch (s.payload) {
                .remark => {},
                .call => |c| {
                    for (c.args) |a| {
                        _ = a;
                    }
                },
                .let => unreachable,
                .@"if" => unreachable,
                .if1 => unreachable,
                .if2 => unreachable,
                .@"for" => unreachable,
                .forstep => unreachable,
                .next => unreachable,
                .jumplabel => unreachable,
                .goto => unreachable,
                .end => unreachable,
                .endif => unreachable,
            }
        }

        return self.buf.toOwnedSlice(self.allocator);
    }
};

pub fn compile(allocator: Allocator, inp: []const u8) ![]const u8 {
    const sx = try parse.parse(allocator, inp);
    defer parse.free(allocator, sx);

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    return try compiler.compile(sx);
}

test "compile shrimple" {
    const code = try compile(testing.allocator,
        \\PRINT 123
        \\
    );
    defer testing.allocator.free(code);

    try testing.expectEqualSlices(u8, "", code);
}
