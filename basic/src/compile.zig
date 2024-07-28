const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const loc = @import("loc.zig");
const ast = @import("ast.zig");
const parse = @import("parse.zig");
const isa = @import("isa.zig");

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

    fn push(self: *Self, e: ast.Expr) !void {
        switch (e.payload) {
            .imm_number => |n| {
                // XXX: only handling INTEGER for now.
                std.debug.assert(n >= -32768 and n <= 32767);
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.PUSH_IMM_INTEGER,
                    isa.Value{ .integer = @truncate(n) },
                });
            },
            .imm_string => |s| {
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.PUSH_IMM_STRING,
                    isa.Value{ .string = s },
                });
            },
            .binop => |b| {
                try self.push(b.lhs.*);
                try self.push(b.rhs.*);
                const opc: isa.Opcode = switch (b.op.payload) {
                    .add => .OPERATOR_ADD,
                    .mul => .OPERATOR_MULTIPLY,
                    else => std.debug.panic("unhandled opcode: {s}", .{@tagName(b.op.payload)}),
                };
                try isa.assembleInto(self.writer, .{opc});
            },
            .paren => |e2| {
                try self.push(e2.*);
            },
            else => std.debug.panic("unhandled Expr type in Compiler.push: {s}", .{@tagName(e.payload)}),
        }
    }

    fn compile(self: *Self, sx: []ast.Stmt) ![]const u8 {
        for (sx) |s| {
            switch (s.payload) {
                .remark => {},
                .call => |c| {
                    for (c.args) |a| {
                        try self.push(a);
                    }
                    if (std.ascii.eqlIgnoreCase(c.name.payload, "print")) {
                        try isa.assembleInto(self.writer, .{
                            isa.Opcode.BUILTIN_PRINT,
                            @as(u8, @intCast(c.args.len)),
                        });
                    } else {
                        std.debug.panic("call to \"{s}\"", .{c.name.payload});
                    }
                },
                .print => |p| {
                    // Each argument gets BUILTIN_PRINTed.
                    // Between arguments, BUILTIN_PRINT_COMMA advances to the next print zone.
                    // At the end, if there's a trailing comma, another BUILTIN_PRINT_COMMA is used.
                    // If there's a trailing semicolon, we do nothing.
                    // Otherwise, we BUILTIN_PRINT_LINEFEED.
                    for (p.args, 0..) |a, i| {
                        try self.push(a);
                        try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT});
                        if (i + 1 < p.separators.len) {
                            switch (p.separators[i].payload) {
                                ';' => {},
                                ',' => try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_COMMA}),
                                else => unreachable,
                            }
                        }
                    }
                    if (p.separators.len == p.args.len) {
                        switch (p.separators[p.args.len - 1].payload) {
                            ';' => {},
                            ',' => try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_COMMA}),
                            else => unreachable,
                        }
                    } else {
                        try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_LINEFEED});
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

pub fn compile(allocator: Allocator, inp: []const u8, errorloc: ?*loc.Loc) ![]const u8 {
    const sx = try parse.parse(allocator, inp, errorloc);
    defer parse.free(allocator, sx);

    var compiler = try Compiler.init(allocator);
    defer compiler.deinit();

    return try compiler.compile(sx);
}

test "compile shrimple" {
    const code = try compile(testing.allocator,
        \\PRINT 123
        \\
    , null);
    defer testing.allocator.free(code);

    const exp = try isa.assemble(testing.allocator, .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 123 },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
    });
    defer testing.allocator.free(exp);

    try testing.expectEqualSlices(u8, exp, code);
}

test "compile less shrimple" {
    const code = try compile(testing.allocator,
        \\PRINT 6 + 5 * 4, 3; 2
        \\
    , null);
    defer testing.allocator.free(code);

    const exp =
        try isa.assemble(testing.allocator, .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 6 },
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 5 },
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 4 },
        isa.Opcode.OPERATOR_MULTIPLY,
        isa.Opcode.OPERATOR_ADD,
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.BUILTIN_PRINT_COMMA,
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 3 },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 2 },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
    });
    defer testing.allocator.free(exp);

    try testing.expectEqualSlices(u8, exp, code);
}
