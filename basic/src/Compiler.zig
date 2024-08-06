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
const stack = @import("stack.zig");

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

    return compiler.compileStmts(sx);
}

pub fn compileText(allocator: Allocator, inp: []const u8, errorinfo: ?*ErrorInfo) ![]const u8 {
    const sx = try Parser.parse(allocator, inp, errorinfo);
    defer Parser.free(allocator, sx);

    return compile(allocator, sx, errorinfo);
}

pub fn init(allocator: Allocator, errorinfo: ?*ErrorInfo) !*Compiler {
    const self = try allocator.create(Compiler);
    self.* = .{
        .allocator = allocator,
        .writer = undefined,
        .errorinfo = errorinfo,
    };
    self.writer = self.buf.writer(allocator);
    return self;
}

pub fn deinit(self: *Compiler) void {
    self.buf.deinit(self.allocator);
    var it = self.slots.keyIterator();
    while (it.next()) |k|
        self.allocator.free(k.*);
    self.slots.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn compileStmts(self: *Compiler, sx: []Stmt) ![]const u8 {
    for (sx) |s|
        try self.compileStmt(s);

    return self.buf.toOwnedSlice(self.allocator);
}

fn compileStmt(self: *Compiler, s: Stmt) !void {
    switch (s.payload) {
        .remark => {},
        .call => |c| {
            for (c.args) |a| {
                _ = try self.compileExpr(a.payload);
            }
            return ErrorInfo.ret(self, Error.Unimplemented, "call to \"{s}\"", .{c.name.payload});
        },
        .print => |p| {
            // Each argument gets BUILTIN_PRINTed.
            // Between arguments, BUILTIN_PRINT_COMMA advances to the next print zone.
            // At the end, if there's a trailing comma, another BUILTIN_PRINT_COMMA is used.
            // If there's a trailing semicolon, we do nothing.
            // Otherwise, we BUILTIN_PRINT_LINEFEED.
            for (p.args, 0..) |a, i| {
                // TODO: probably want BUILTIN_PRINT_{type}.
                _ = try self.compileExpr(a.payload);
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
            const resolved = try self.labelResolve(l.lhs.payload, .write);
            const rhsType = try self.compileExpr(l.rhs.payload);
            try self.compileCoerce(rhsType, resolved.type);
            try isa.assembleInto(self.writer, .{
                isa.Opcode.LET,
                resolved.slot,
            });
        },
        .pragma_printed => |p| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PRAGMA_PRINTED,
                isa.Value{ .string = p.payload },
            });
        },
        else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled stmt: {s}", .{@tagName(s.payload)}),
    }
}

fn compileExpr(self: *Compiler, e: Expr.Payload) (Allocator.Error || Error)!ty.Type {
    switch (e) {
        .imm_integer => |n| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_INTEGER,
                isa.Value{ .integer = n },
            });
            return .integer;
        },
        .imm_long => |n| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_LONG,
                isa.Value{ .long = n },
            });
            return .long;
        },
        .imm_single => |n| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_SINGLE,
                isa.Value{ .single = n },
            });
            return .single;
        },
        .imm_double => |n| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_DOUBLE,
                isa.Value{ .double = n },
            });
            return .double;
        },
        .imm_string => |s| {
            try isa.assembleInto(self.writer, .{
                isa.Opcode.PUSH_IMM_STRING,
                isa.Value{ .string = s },
            });
            return .string;
        },
        .label => |l| {
            const resolved = try self.labelResolve(l, .read);
            if (resolved.slot) |slot| {
                try isa.assembleInto(self.writer, .{
                    isa.Opcode.PUSH_VARIABLE,
                    slot,
                });
            } else {
                // autovivify
                _ = try self.compileExpr(Expr.Payload.zeroImm(resolved.type));
            }
            return resolved.type;
        },
        .binop => |b| {
            const tyx = try self.compileBinopOperands(b.lhs.payload, b.op.payload, b.rhs.payload);

            const opc: isa.Opcode = switch (b.op.payload) {
                .add => switch (tyx.widened) {
                    .integer => .OPERATOR_ADD_INTEGER,
                    .long => .OPERATOR_ADD_LONG,
                    .single => .OPERATOR_ADD_SINGLE,
                    .double => .OPERATOR_ADD_DOUBLE,
                    .string => .OPERATOR_ADD_STRING,
                },
                .mul => switch (tyx.widened) {
                    .integer => .OPERATOR_MULTIPLY_INTEGER,
                    .long => .OPERATOR_MULTIPLY_LONG,
                    .single => .OPERATOR_MULTIPLY_SINGLE,
                    .double => .OPERATOR_MULTIPLY_DOUBLE,
                    .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot multiply a STRING", .{}),
                },
                .fdiv => switch (tyx.widened) {
                    .integer => .OPERATOR_FDIVIDE_INTEGER,
                    .long => .OPERATOR_FDIVIDE_LONG,
                    .single => .OPERATOR_FDIVIDE_SINGLE,
                    .double => .OPERATOR_FDIVIDE_DOUBLE,
                    .string => unreachable,
                },
                .idiv => switch (tyx.widened) {
                    .integer => .OPERATOR_IDIVIDE_INTEGER,
                    .long => .OPERATOR_IDIVIDE_LONG,
                    .single => .OPERATOR_IDIVIDE_SINGLE,
                    .double => .OPERATOR_IDIVIDE_DOUBLE,
                    .string => unreachable,
                },
                .sub => switch (tyx.widened) {
                    .integer => .OPERATOR_SUBTRACT_INTEGER,
                    .long => .OPERATOR_SUBTRACT_LONG,
                    .single => .OPERATOR_SUBTRACT_SINGLE,
                    .double => .OPERATOR_SUBTRACT_DOUBLE,
                    .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot subtract a STRING", .{}),
                },
                else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled opc: {s}", .{@tagName(b.op.payload)}),
            };
            try isa.assembleInto(self.writer, .{opc});

            return tyx.result;
        },
        .paren => |e2| return try self.compileExpr(e2.payload),
        .negate => |e2| {
            const resultType = try self.compileExpr(e2.payload);
            const op: isa.Opcode = switch (resultType) {
                .integer => .OPERATOR_NEGATE_INTEGER,
                .long => .OPERATOR_NEGATE_LONG,
                .single => .OPERATOR_NEGATE_SINGLE,
                .double => .OPERATOR_NEGATE_DOUBLE,
                .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot negate a STRING", .{}),
            };
            try isa.assembleInto(self.writer, .{op});
            return resultType;
        },
        // else => return ErrorInfo.ret(self, Error.Unimplemented, "unhandled Expr type in Compiler.push: {s}", .{@tagName(e.payload)}),
    }
}

fn compileCoerce(self: *Compiler, from: ty.Type, to: ty.Type) !void {
    if (from == to) return;

    const op: isa.Opcode = switch (from) {
        .integer => switch (to) {
            .integer => unreachable,
            .long => .PROMOTE_INTEGER_LONG,
            .single => .COERCE_INTEGER_SINGLE,
            .double => .COERCE_INTEGER_DOUBLE,
            .string => return self.cannotCoerce(from, to),
        },
        .long => switch (to) {
            .integer => .COERCE_LONG_INTEGER,
            .long => unreachable,
            .single => .COERCE_LONG_SINGLE,
            .double => .COERCE_LONG_DOUBLE,
            .string => return self.cannotCoerce(from, to),
        },
        .single => switch (to) {
            .integer => .COERCE_SINGLE_INTEGER,
            .long => .COERCE_SINGLE_LONG,
            .single => unreachable,
            .double => .PROMOTE_SINGLE_DOUBLE,
            .string => return self.cannotCoerce(from, to),
        },
        .double => switch (to) {
            .integer => .COERCE_DOUBLE_INTEGER,
            .long => .COERCE_DOUBLE_LONG,
            .single => .COERCE_DOUBLE_SINGLE,
            .double => unreachable,
            .string => return self.cannotCoerce(from, to),
        },
        .string => return self.cannotCoerce(from, to),
    };

    try isa.assembleInto(self.writer, .{op});
}

fn cannotCoerce(self: *const Compiler, from: ty.Type, to: ty.Type) (Error || Allocator.Error) {
    return ErrorInfo.ret(self, Error.TypeMismatch, "cannot coerce {any} to {any}", .{ from, to });
}

const BinopTypes = struct {
    widened: ty.Type,
    result: ty.Type,
};

fn compileBinopOperands(self: *Compiler, lhs: Expr.Payload, op: Expr.Op, rhs: Expr.Payload) !BinopTypes {
    const lhsType = try self.compileExpr(lhs);

    // Compile RHS to get type; snip off the generated code and append after we
    // do any necessary coercion. (It was either this or do stack swapsies in
    // the generated code.)
    const index = self.buf.items.len;
    const rhsType = try self.compileExpr(rhs);
    const rhsCode = try self.allocator.dupe(u8, self.buf.items[index..]);
    defer self.allocator.free(rhsCode);
    self.buf.items.len = index;

    // Coerce both types to the wider of the two (if possible).
    const widenedType = lhsType.widen(rhsType) orelse return self.cannotCoerce(rhsType, lhsType);
    try self.compileCoerce(lhsType, widenedType);

    try self.writer.writeAll(rhsCode);
    try self.compileCoerce(rhsType, widenedType);

    // Determine the type of the result of the operation, which might differ
    // from the input type (fdiv, idiv). The former is necessary for the
    // compilation to know what was placed on the stack; the latter is necessary
    // to determine which opcode to produce.
    const resultType: ty.Type = switch (op) {
        .mul => widenedType,
        .fdiv => switch (widenedType) {
            .integer, .single => .single,
            .long, .double => .double,
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot fdivide a STRING", .{}),
        },
        .idiv => switch (widenedType) {
            .integer, .single => .integer,
            .long, .double => .long,
            .string => return ErrorInfo.ret(self, Error.TypeMismatch, "cannot idivide a STRING", .{}),
        },
        .add => widenedType,
        .sub => widenedType,
        else => unreachable,
    };

    return .{ .widened = widenedType, .result = resultType };
}

const Rw = enum { read, write };

fn ResolvedLabel(comptime rw: Rw) type {
    return if (rw == .read) struct {
        slot: ?u8 = null,
        type: ty.Type,
    } else struct {
        slot: u8,
        type: ty.Type,
    };
}

fn labelResolve(self: *Compiler, l: []const u8, comptime rw: Rw) !ResolvedLabel(rw) {
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

    if (self.slots.getEntry(key)) |e| {
        self.allocator.free(key);
        return .{ .slot = e.value_ptr.*, .type = typ };
    } else if (rw == .read) {
        // autovivify
        self.allocator.free(key);
        return .{ .type = typ };
    } else {
        errdefer self.allocator.free(key);
        const slot = self.nextslot;
        self.nextslot += 1;
        try self.slots.putNoClobber(self.allocator, key, slot);
        return .{ .slot = slot, .type = typ };
    }
}

fn expectCompile(input: []const u8, assembly: anytype) !void {
    const code = try compileText(testing.allocator, input, null);
    defer testing.allocator.free(code);

    const exp = try isa.assemble(testing.allocator, assembly);
    defer testing.allocator.free(exp);

    try testing.expectEqualSlices(u8, exp, code);
}

test "compile shrimple" {
    try expectCompile(
        \\PRINT 123
        \\
    , .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 123 },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
    });
}

test "compile less shrimple" {
    try expectCompile(
        \\PRINT 6 + 5 * 4, 3; 2
        \\
    , .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 6 },
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 5 },
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 4 },
        isa.Opcode.OPERATOR_MULTIPLY_INTEGER,
        isa.Opcode.OPERATOR_ADD_INTEGER,
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
}

test "compile variable access" {
    try expectCompile(
        \\a% = 12
        \\b% = 34
        \\c% = a% + b%
    , .{
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
        isa.Opcode.OPERATOR_ADD_INTEGER,
        isa.Opcode.LET,
        2,
    });
}

test "compile (parse) error" {
    var errorinfo: ErrorInfo = .{};
    const eu = compileText(testing.allocator, " 1", &errorinfo);
    try testing.expectError(error.UnexpectedToken, eu);
    try testing.expectEqual(ErrorInfo{ .loc = Loc{ .row = 1, .col = 2 } }, errorinfo);
}

fn expectCompileErr(inp: []const u8, err: anyerror, msg: ?[]const u8) !void {
    var errorinfo: ErrorInfo = .{};
    defer errorinfo.clear(testing.allocator);
    const eu = compileText(testing.allocator, inp, &errorinfo);
    defer if (eu) |code| {
        testing.allocator.free(code);
    } else |_| {};
    try testing.expectError(err, eu);
    try testing.expectEqualDeep(msg, errorinfo.msg);
}

test "variable type mismatch" {
    try expectCompileErr(
        \\a="x"
    , Error.TypeMismatch, "cannot coerce STRING to SINGLE");
}

test "promotion and coercion" {
    try expectCompile(
        \\a% = 1 + 1.5 * 100000
    , .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 1 },
        isa.Opcode.COERCE_INTEGER_SINGLE,
        isa.Opcode.PUSH_IMM_SINGLE,
        isa.Value{ .single = 1.5 },
        isa.Opcode.PUSH_IMM_LONG,
        isa.Value{ .long = 100000 },
        isa.Opcode.COERCE_LONG_SINGLE,
        isa.Opcode.OPERATOR_MULTIPLY_SINGLE,
        isa.Opcode.OPERATOR_ADD_SINGLE,
        isa.Opcode.COERCE_SINGLE_INTEGER,
        isa.Opcode.LET,
        0,
    });
}

test "autovivification" {
    try expectCompile(
        \\PRINT a%; a$
    , .{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 0 },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.PUSH_IMM_STRING,
        isa.Value{ .string = "" },
        isa.Opcode.BUILTIN_PRINT,
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
    });
}

test "compiler and stack machine agree on binop expression types" {
    const tyx: []const ty.Type = &.{ .integer, .long, .single, .double, .string };
    const ops: []const Expr.Op = &.{ .mul, .fdiv, .idiv, .add, .sub };
    // TODO: .eq, .neq, .lt, .gt, .lte, .gte, @"and", @"or", xor

    for (ops) |op| {
        for (tyx) |tyLhs| {
            for (tyx) |tyRhs| {
                var c = try Compiler.init(testing.allocator, null);
                defer c.deinit();

                var lhs = Expr.init(Expr.Payload.oneImm(tyLhs), .{});
                var rhs = Expr.init(Expr.Payload.oneImm(tyRhs), .{});

                const compilerTy = c.compileExpr(.{ .binop = .{
                    .lhs = &lhs,
                    .op = loc.WithRange(Expr.Op).init(op, .{}),
                    .rhs = &rhs,
                } }) catch |err| switch (err) {
                    Error.TypeMismatch => continue, // keelatud eine
                    else => return err,
                };

                var m = stack.Machine(stack.TestEffects).init(testing.allocator, try stack.TestEffects.init(), null);
                defer m.deinit();

                const code = try c.buf.toOwnedSlice(testing.allocator);
                defer testing.allocator.free(code);

                try m.run(code);

                try testing.expectEqual(1, m.stack.items.len);
                // Stack machine output is considered expected, as it's written
                // more plainly.
                testing.expectEqual(m.stack.items[0].type(), compilerTy) catch |err| {
                    std.debug.print("op: {any}; tyLhs: {any}; tyRhs: {any}\n", .{ op, tyLhs, tyRhs });
                    return err;
                };
            }
        }
    }
}
