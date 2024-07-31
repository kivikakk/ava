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
const ty = @import("ty.zig");

const Compiler = @This();

allocator: Allocator,
buf: std.ArrayListUnmanaged(u8) = .{},
writer: std.ArrayListUnmanaged(u8).Writer,
errorinfo: ?*ErrorInfo,

deftypes: [26]ty.Type = [_]ty.Type{.single} ** 26,
slots: std.StringHashMapUnmanaged(u8) = .{}, // key is UPPERCASE with sigil
nextslot: u8 = 0,

const Error = error{
    Unimplemented,
    TypeMismatch,
    Overflow,
};

pub fn compile(allocator: Allocator, sx: []Stmt, errorinfo: ?*ErrorInfo) ![]const u8 {
    var compiler = try init(allocator, errorinfo);
    defer compiler.deinit();

    return try compiler.compileSx(sx);
}

pub fn compileText(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) ![]const u8 {
    const sx = try Parser.parse(allocator, inp, errorinfo);
    defer Parser.free(allocator, sx);

    return compile(allocator, sx, errorinfo);
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
    var it = self.slots.keyIterator();
    while (it.next()) |k|
        self.allocator.free(k.*);
    self.slots.deinit(self.allocator);
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
                const resolved = try self.labelResolve(l.lhs.payload);
                const rhsType = try self.typeInfer(l.rhs);
                if (rhsType != resolved.type)
                    return ErrorInfo.ret(self, Error.TypeMismatch, "expected type {any}, got {any}", .{ resolved.type, rhsType });
                try self.push(l.rhs);
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.LET,
                    resolved.slot,
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
            const resolved = try self.labelResolve(l);
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_VARIABLE,
                resolved.slot,
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

const ResolvedLabel = struct {
    slot: u8,
    type: ty.Type,
};

pub fn labelResolve(self: *Compiler, l: []const u8) !ResolvedLabel {
    std.debug.assert(l.len > 0);

    var key: []u8 = undefined;
    var typ: ty.Type = undefined;

    if (ty.Type.fromSigil(l[l.len - 1])) |t| {
        key = try self.allocator.alloc(u8, l.len);
        _ = std.ascii.upperString(key, l);

        typ = t;
    } else {
        key = try self.allocator.alloc(u8, l.len + 1);
        _ = std.ascii.upperString(key, l);

        std.debug.assert(key[0] >= 'A' and key[0] <= 'Z');
        typ = self.deftypes[key[0] - 'A'];
        key[l.len] = typ.sigil();
    }

    var slot: u8 = undefined;

    if (self.slots.getEntry(key)) |e| {
        self.allocator.free(key);
        slot = e.value_ptr.*;
    } else {
        errdefer self.allocator.free(key);
        slot = self.nextslot;
        self.nextslot += 1;

        try self.slots.putNoClobber(self.allocator, key, slot);
    }

    return .{ .slot = slot, .type = typ };
}

pub fn typeInfer(self: *const Compiler, e: Expr) !ty.Type {
    // XXX awful.
    return switch (e.payload) {
        .imm_number => |i| if (i >= -std.math.pow(isize, 2, 15) and i <= std.math.pow(isize, 2, 15) - 1)
            .integer
        else if (i >= -std.math.pow(isize, 2, 31) and i <= std.math.pow(isize, 2, 31) - 1)
            .long
        else
            // XXX: double? See Compiler.push.
            error.Overflow,
        .imm_string => .string,
        .label => |l| l: {
            // XXX consult slot list
            break :l ty.Type.forLabel(l);
        },
        .binop => |b| b: {
            // XXX: 2 * 2.5? 2.5 * 2? 2.0 * 2?
            // XXX: For now, accept same type only.
            const l = try self.typeInfer(b.lhs.*);
            const r = try self.typeInfer(b.rhs.*);
            if (l != r)
                return ErrorInfo.ret(self, Error.TypeMismatch, "binop type mismatch XXX {any} != {any}", .{ l, r });
            break :b l;
        },
        .paren, .negate => |e2| self.typeInfer(e2.*),
    };
}

test "compile shrimple" {
    const code = try compileText(testing.allocator,
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
    const code = try compileText(testing.allocator,
        \\PRINT 6 + 5 * 4, 3; 2
        \\
    , null);
    defer testing.allocator.free(code);

    const exp = try isa.assemble(testing.allocator, .{
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

test "compile variable access" {
    const code = try compileText(testing.allocator,
        \\a% = 12
        \\b% = 34
        \\c% = a% + b%
    , null);
    defer testing.allocator.free(code);

    const exp = try isa.assemble(testing.allocator, .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 12 },
        isa.Opcode.LET,
        0,
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 34 },
        isa.Opcode.LET,
        1,
        isa.Opcode.PUSH_VARIABLE,
        0,
        isa.Opcode.PUSH_VARIABLE,
        1,
        isa.Opcode.OPERATOR_ADD,
        isa.Opcode.LET,
        2,
    });
    defer testing.allocator.free(exp);

    try testing.expectEqualSlices(u8, exp, code);
}

test "compile (parse) error" {
    var errorinfo: ErrorInfo = .{};
    const eu = compileText(testing.allocator, " 1", &errorinfo);
    try testing.expectError(error.UnexpectedToken, eu);
    try testing.expectEqual(ErrorInfo{ .loc = Loc{ .row = 1, .col = 2 } }, errorinfo);
}

fn testerr(inp: []const u8, err: anyerror, msg: ?[]const u8) !void {
    var errorinfo: ErrorInfo = .{};
    defer errorinfo.clear(testing.allocator);
    const eu = compileText(testing.allocator, inp, &errorinfo);
    defer if (eu) |code| {
        testing.allocator.free(code);
    } else |_| {};
    try testing.expectError(err, eu);
    try testing.expectEqualDeep(msg, errorinfo.msg);
}

test "variable type match" {
    try testerr(
        \\a="x"
    , Error.TypeMismatch, "expected type SINGLE, got STRING");
}
