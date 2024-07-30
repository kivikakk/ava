const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const loc = @import("loc.zig");
const Loc = loc.Loc;
const Stmt = @import("ast/Stmt.zig");
const Expr = @import("ast/Expr.zig");
const Parser = @import("Parser.zig");
const isa = @import("isa.zig");
const ErrorInfo = @import("ErrorInfo.zig");

const Compiler = @This();

allocator: Allocator,
buf: std.ArrayListUnmanaged(u8) = .{},
writer: std.ArrayListUnmanaged(u8).Writer,
errorinfo: ?*ErrorInfo,

const Error = error{
    Unimplemented,
    TypeMismatch,
    Overflow,
};

pub fn compileStmts(allocator: Allocator, sx: []Stmt, errorinfo: ?*ErrorInfo) ![]const u8 {
    var compiler = try init(allocator, errorinfo);
    defer compiler.deinit();

    return try compiler.compileSx(sx);
}

pub fn compile(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) ![]const u8 {
    const sx = try Parser.parse(allocator, inp, errorinfo);
    defer Parser.free(allocator, sx);

    return compileStmts(allocator, sx, errorinfo);
}

fn init(allocator: Allocator, errorinfo: ?*ErrorInfo) !*Compiler {
    const self = try allocator.create(Compiler);
    self.* = .{
        .allocator = allocator,
        .writer = undefined,
        .errorinfo = errorinfo,
    };
    self.writer = self.buf.writer(allocator);
    return self;
}

fn deinit(self: *Compiler) void {
    self.buf.deinit(self.allocator);
    self.allocator.destroy(self);
}

fn compileSx(self: *Compiler, sx: []Stmt) ![]const u8 {
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
                    return ErrorInfo.ret(self, Error.Unimplemented, "call to \"{s}\"", .{c.name.payload});
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
                    if (i < p.separators.len) {
                        switch (p.separators[i].payload) {
                            ';' => {},
                            ',' => try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_COMMA}),
                            else => unreachable,
                        }
                    }
                }
                if (p.separators.len == p.args.len and p.separators.len > 0) {
                    switch (p.separators[p.args.len - 1].payload) {
                        ';' => {},
                        ',' => try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_COMMA}),
                        else => unreachable,
                    }
                } else {
                    try isa.assembleInto(self.writer, .{isa.Opcode.BUILTIN_PRINT_LINEFEED});
                }
            },
            .let => |l| {
                try self.push(l.rhs);
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.LET,
                    l.lhs.payload,
                });
            },
            else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled stmt: {s}", .{@tagName(s.payload)}),
        }
    }

    return self.buf.toOwnedSlice(self.allocator);
}

fn push(self: *Compiler, e: Expr) !void {
    switch (e.payload) {
        .imm_number => |n| {
            if (n >= -std.math.pow(isize, 2, 15) and n <= std.math.pow(isize, 2, 15) - 1) {
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.PUSH_IMM_INTEGER,
                    isa.Value{ .integer = @truncate(n) },
                });
            } else if (n >= std.math.pow(isize, 2, 31) and n <= std.math.pow(isize, 2, 31) - 1) {
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.PUSH_IMM_LONG,
                    isa.Value{ .long = @truncate(n) },
                });
            } else {
                // XXX: QBASIC normalises these to doubles.
                return Error.Overflow;
            }
        },
        .imm_string => |s| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_STRING,
                isa.Value{ .string = s },
            });
        },
        .label => |l| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_VARIABLE,
                l,
            });
        },
        .binop => |b| {
            try self.push(b.lhs.*);
            try self.push(b.rhs.*);
            const opc: isa.Opcode = switch (b.op.payload) {
                .add => .OPERATOR_ADD,
                .mul => .OPERATOR_MULTIPLY,
                else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled opcode: {s}", .{@tagName(b.op.payload)}),
            };
            try isa.assembleInto(self.writer, .{opc});
        },
        .paren => |e2| try self.push(e2.*),
        .negate => |e2| {
            try self.push(e2.*);
            try isa.assembleInto(self.writer, .{isa.Opcode.OPERATOR_NEGATE});
        },
        // else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled Expr type in Compiler.push: {s}", .{@tagName(e.payload)}),
    }
}

// XXX: DEFINT/DEFLNG/DEFSNG/DEFDBL/DEFSTR
const Type = enum {
    integer, // % or none
    long, // &
    single, // !
    double, // #
    string, // $
};

fn varType(label: []const u8) Type {
    std.debug.assert(label.len > 0);
    return switch (label[label.len - 1]) {
        '%' => .integer,
        '&' => .long,
        '!' => .single,
        '#' => .double,
        '$' => .string,
        else => .integer,
    };
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

test "compile (parse) error" {
    var errorinfo: ErrorInfo = .{};
    const eu = compile(testing.allocator, " 1", &errorinfo);
    try testing.expectError(error.UnexpectedToken, eu);
    try testing.expectEqual(ErrorInfo{ .loc = Loc{ .row = 1, .col = 2 } }, errorinfo);
}

fn testerr(inp: []const u8, err: anyerror, msg: ?[]const u8) !void {
    var errorinfo: ErrorInfo = .{};
    defer errorinfo.clear(testing.allocator);
    const eu = compile(testing.allocator, inp, &errorinfo);
    defer if (eu) |code| {
        testing.allocator.free(code);
    } else |_| {};
    try testing.expectError(err, eu);
    try testing.expectEqualDeep(msg, errorinfo.msg);
}

test "variable type match" {
    try testerr(
        \\a="x"
    , Error.TypeMismatch, "expected type integer, got string");
}
