const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const parse = @import("parse.zig");
const stack = @import("stack.zig");

const Compiler = struct {
    const Self = @This();

    allocator: Allocator,
    buf: std.ArrayListUnmanaged(u8) = .{},
    writer: std.ArrayListUnmanaged(u8).Writer,

    fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .writer = undefined,
        };
        self.writer = self.buf.writer(allocator);
        return self;
    }

    fn deinit(self: *Self) void {
        self.buf.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    fn push(self: *Self, e: parse.Expr) !void {
        switch (e.payload) {
            .imm_number => |n| {
                // XXX: only handling INTEGER for now.
                std.debug.assert(n >= -32768 and n <= 32767);
                const nt: i16 = @truncate(n);
                try stack.assembleInto(.{
                    stack.Opcode.PUSH_IMM_INTEGER,
                    stack.Value{ .integer = nt },
                }, self.writer.any());
            },
            else => std.debug.panic("unhandled Expr type in Compiler.push: {any}", .{@tagName(e.payload)}),
        }
    }

    fn compile(self: *Self, sx: []parse.Stmt) ![]const u8 {
        for (sx) |s| {
            switch (s.payload) {
                .remark => {},
                .call => |c| {
                    for (c.args) |a| {
                        try self.push(a);
                    }
                    if (std.ascii.eqlIgnoreCase(c.name.payload, "print")) {
                        try stack.assembleInto(.{
                            stack.Opcode.BUILTIN_PRINT,
                            @as(u8, @intCast(c.args.len)),
                        }, self.writer.any());
                    } else {
                        std.debug.panic("call to \"{s}\"", .{c.name.payload});
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

    var compiler = try Compiler.init(allocator);
    defer compiler.deinit();

    return try compiler.compile(sx);
}

test "compile shrimple" {
    const code = try compile(testing.allocator,
        \\PRINT 123
        \\
    );
    defer testing.allocator.free(code);

    try testing.expectEqualSlices(u8, stack.assemble(.{
        stack.Opcode.PUSH_IMM_INTEGER,
        stack.Value{ .integer = 123 },
        stack.Opcode.BUILTIN_PRINT,
        1,
    }), code);
}
