const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const ty = @import("ty.zig");
const Expr = @import("ast/Expr.zig");

pub const Type = enum(u3) {
    INTEGER = 0b000,
    LONG = 0b001,
    SINGLE = 0b010,
    DOUBLE = 0b011,
    STRING = 0b100,

    pub fn fromTy(t: ty.Type) Type {
        return switch (t) {
            .integer => .INTEGER,
            .long => .LONG,
            .single => .SINGLE,
            .double => .DOUBLE,
            .string => .STRING,
        };
    }
};

pub const TypeCast = enum(u2) {
    INTEGER = 0b00,
    LONG = 0b01,
    SINGLE = 0b10,
    DOUBLE = 0b11,

    pub fn fromTy(t: ty.Type) TypeCast {
        return switch (t) {
            .integer => .INTEGER,
            .long => .LONG,
            .single => .SINGLE,
            .double => .DOUBLE,
            .string => unreachable,
        };
    }
};

pub const Op = enum(u4) {
    PUSH = 0b0001,
    CAST = 0b0010,
    LET = 0b0011,
    PRINT = 0b0100,
    PRINT_COMMA = 0b0101, // TODO: use space in rest of opcode for this
    PRINT_LINEFEED = 0b0110, // and this.
    ALU = 0b0111,
    PRAGMA = 0b1110,
};

pub const AluOp = enum(u5) {
    ADD = 0b00000,
    MUL = 0b00001,
    FDIV = 0b00010,
    IDIV = 0b00011,
    SUB = 0b00100,
    // NEG = 0b00101, // XXX unimpl
    EQ = 0b00110,
    NEQ = 0b00111,
    LT = 0b01000,
    GT = 0b01001,
    LTE = 0b01010,
    GTE = 0b01011,
    AND = 0b01100,
    OR = 0b01101,
    XOR = 0b01110,
    MOD = 0b01111,

    pub fn fromExprOp(op: Expr.Op) AluOp {
        return switch (op) {
            .add => .ADD,
            .mul => .MUL,
            .fdiv => .FDIV,
            .idiv => .IDIV,
            .sub => .SUB,
            .eq => .EQ,
            .neq => .NEQ,
            .lt => .LT,
            .gt => .GT,
            .lte => .LTE,
            .gte => .GTE,
            .@"and" => .AND,
            .@"or" => .OR,
            .xor => .XOR,
            .mod => .MOD,
        };
    }
};

pub const InsnX = packed struct(u8) {
    op: Op,
    rest: u4 = 0,
};

pub const InsnT = packed struct(u8) {
    op: Op,
    t: Type,
    rest: u1 = 0,
};

pub const InsnTC = packed struct(u8) {
    op: Op,
    tf: TypeCast,
    tt: TypeCast,
};

pub const InsnAlu = packed struct(u16) {
    op: Op,
    t: Type,
    alu: AluOp,
    rest: u4 = 0,
};

pub const Opcode = struct {
    op: Op,
    t: ?Type = null,
    tc: ?struct { from: TypeCast, to: TypeCast } = null,
    alu: ?AluOp = null,
    slot: ?u8 = null,
};

pub const Value = union(enum) {
    const Self = @This();

    integer: i16,
    long: i32,
    single: f32,
    double: f64,
    string: []const u8,

    pub fn @"type"(self: Self) ty.Type {
        return switch (self) {
            .integer => .integer,
            .long => .long,
            .single => .single,
            .double => .double,
            .string => .string,
        };
    }

    pub fn clone(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .integer, .long, .single, .double => self,
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
        };
    }
};

pub fn printFormat(allocator: Allocator, writer: anytype, v: Value) !void {
    switch (v) {
        .integer => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try std.fmt.format(writer, "{d} ", .{n});
        },
        .long => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try std.fmt.format(writer, "{d} ", .{n});
        },
        .single => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try printFormatFloating(allocator, writer, n);
            try writer.writeByte(' ');
        },
        .double => |n| {
            if (n >= 0)
                try writer.writeByte(' ');
            try printFormatFloating(allocator, writer, n);
            try writer.writeByte(' ');
        },
        .string => |s| try writer.writeAll(s),
    }
}

fn printFormatFloating(allocator: Allocator, writer: anytype, f: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, "{d}", .{f});
    defer allocator.free(s);

    var len = s.len;
    // QB accepts and prefers ".1" and "-.1".
    if (std.mem.startsWith(u8, s, "0.")) {
        std.mem.copyForwards(u8, s, s[1..]);
        len -= 1;
    } else if (std.mem.startsWith(u8, s, "-0.")) {
        std.mem.copyForwards(u8, s[1..], s[2..]);
        len -= 1;
    }

    // Round the last digit(s) to match QBASIC.
    //
    // This is an enormous hack and I don't like it. Is precise compatibility
    // worth this? Is there a better way to do it that'd more closely follow how
    // QB actually works?
    var hasPoint = false;
    for (s[0..len]) |c|
        if (c == '.') {
            hasPoint = true;
            break;
        };

    if (hasPoint) {
        var digits = len - 1;
        if (s[0] == '-') digits -= 1;
        const cap = switch (@TypeOf(f)) {
            f32 => 8,
            f64 => 16,
            else => @compileError("printFormatFloating given f " ++ @typeName(@TypeOf(f))),
        };
        while (digits >= cap) : (digits -= 1) {
            std.debug.assert(s[len - 1] >= '0' and s[len - 1] <= '9');
            std.debug.assert(s[len - 2] >= '0' and s[len - 2] <= '9');
            if (s[len - 1] >= '5') {
                if (!(s[len - 2] >= '0' and s[len - 2] <= '8')) {
                    // Note to self: I fully expect this won't be sufficient and
                    // we'll have to iterate backwards. Sorry.
                    std.debug.panic("nope: '{s}'", .{s[0..len]});
                }
                std.debug.assert(s[len - 2] <= '8');
                s[len - 2] += 1;
                len -= 1;
            } else {
                len -= 1;
            }
        }
    }

    try writer.writeAll(s[0..len]);
}

pub fn assembleOne(e: anytype, writer: anytype) !void {
    switch (@TypeOf(e)) {
        Opcode => {
            switch (e.op) {
                .PUSH => {
                    if (e.slot) |slot| {
                        std.debug.assert(e.t == null);
                        const insn = InsnX{ .op = e.op, .rest = 0b1000 };
                        try writer.writeInt(u8, @bitCast(insn), .little);
                        try writer.writeInt(u8, slot, .little);
                    } else {
                        const insn = InsnT{ .op = e.op, .t = e.t.? };
                        try writer.writeInt(u8, @bitCast(insn), .little);
                    }
                },
                .CAST => {
                    const insn = InsnTC{ .op = e.op, .tf = e.tc.?.from, .tt = e.tc.?.to };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .LET => {
                    const insn = InsnX{ .op = e.op };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                    try writer.writeInt(u8, e.slot.?, .little);
                },
                .PRINT => {
                    const insn = InsnT{ .op = e.op, .t = e.t.? };
                    std.debug.assert(e.slot == null);
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .PRINT_COMMA, .PRINT_LINEFEED, .PRAGMA => {
                    const insn = InsnX{ .op = e.op };
                    try writer.writeInt(u8, @bitCast(insn), .little);
                },
                .ALU => {
                    const insn = InsnAlu{ .op = e.op, .t = e.t.?, .alu = e.alu.? };
                    try writer.writeInt(u16, @bitCast(insn), .little);
                },
            }
        },
        Value => {
            switch (e) {
                .integer => |i| try writer.writeInt(i16, i, .little),
                .long => |i| try writer.writeInt(i32, i, .little),
                .single => |n| try writer.writeStruct(packed struct { n: f32 }{ .n = n }),
                .double => |n| try writer.writeStruct(packed struct { n: f64 }{ .n = n }),
                .string => |s| {
                    try writer.writeInt(u16, @as(u16, @intCast(s.len)), .little);
                    try writer.writeAll(s);
                },
            }
        },
        []const u8 => {
            // label; one byte for length.
            try writer.writeByte(@intCast(e.len));
            try writer.writeAll(e);
        },
        else => @panic("unhandled type: " ++ @typeName(@TypeOf(e))),
    }
}

pub fn assembleInto(writer: anytype, inp: anytype) !void {
    inline for (inp) |e|
        try assembleOne(e, writer);
}

pub fn assemble(allocator: Allocator, inp: anytype) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    try assembleInto(out.writer(allocator), inp);
    return try out.toOwnedSlice(allocator);
}

fn expectAssembles(inp: anytype, expected: []const u8) !void {
    const code = try assemble(testing.allocator, inp);
    defer testing.allocator.free(code);
    try testing.expectEqualSlices(u8, expected, code);
}

test "assembles" {
    try expectAssembles(.{
        Opcode{ .op = .PUSH, .t = .INTEGER },
        Value{ .integer = 0x7fff },
    }, &.{ 0x01, 0xff, 0x7f });

    try expectAssembles(.{
        Opcode{ .op = .PUSH, .slot = 0x7b },
    }, &.{ 0x81, 0x7b });

    try expectAssembles(.{
        Opcode{ .op = .PUSH, .t = .STRING },
        Value{ .string = "Eks" },
        Opcode{ .op = .PRINT, .t = .STRING },
    }, &.{ 0x41, 0x03, 0x00, 'E', 'k', 's', 0x44 });

    try expectAssembles(.{
        Opcode{ .op = .CAST, .tc = .{ .from = .INTEGER, .to = .LONG } },
        Opcode{ .op = .CAST, .tc = .{ .from = .LONG, .to = .INTEGER } },
        Opcode{ .op = .CAST, .tc = .{ .from = .SINGLE, .to = .DOUBLE } },
        Opcode{ .op = .CAST, .tc = .{ .from = .DOUBLE, .to = .SINGLE } },
    }, &.{ 0x42, 0x12, 0xe2, 0xb2 });

    try expectAssembles(.{
        Opcode{ .op = .LET, .slot = 0xa1 },
    }, &.{ 0x03, 0xa1 });

    try expectAssembles(.{
        Opcode{ .op = .PRINT_COMMA },
        Opcode{ .op = .PRINT_LINEFEED },
    }, &.{ 0x05, 0x06 });

    try expectAssembles(.{
        Opcode{ .op = .ALU, .t = .STRING, .alu = .ADD },
        Opcode{ .op = .ALU, .t = .SINGLE, .alu = .MUL },
        Opcode{ .op = .ALU, .t = .DOUBLE, .alu = .LTE },
    }, &.{ 0x47, 0x00, 0xa7, 0x00, 0x37, 0x05 });

    try expectAssembles(.{
        Opcode{ .op = .PRAGMA },
    }, &.{0x0e});
}
