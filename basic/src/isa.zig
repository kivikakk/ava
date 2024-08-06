const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const ty = @import("ty.zig");

pub const Opcode = enum(u8) {
    PUSH_IMM_INTEGER = 0x01,
    PUSH_IMM_LONG = 0x02,
    PUSH_IMM_SINGLE = 0x03,
    PUSH_IMM_DOUBLE = 0x04,
    PUSH_IMM_STRING = 0x05,
    PUSH_VARIABLE = 0x0a,
    PROMOTE_INTEGER_LONG = 0x10,
    COERCE_INTEGER_SINGLE = 0x11,
    COERCE_INTEGER_DOUBLE = 0x12,
    COERCE_LONG_INTEGER = 0x13,
    COERCE_LONG_SINGLE = 0x14,
    COERCE_LONG_DOUBLE = 0x15,
    COERCE_SINGLE_INTEGER = 0x16,
    COERCE_SINGLE_LONG = 0x17,
    PROMOTE_SINGLE_DOUBLE = 0x18,
    COERCE_DOUBLE_INTEGER = 0x19,
    COERCE_DOUBLE_LONG = 0x1a,
    COERCE_DOUBLE_SINGLE = 0x1b,
    LET = 0x20,
    BUILTIN_PRINT = 0x80,
    BUILTIN_PRINT_COMMA = 0x81,
    BUILTIN_PRINT_LINEFEED = 0x82,
    OPERATOR_ADD_INTEGER = 0xa0,
    OPERATOR_ADD_LONG = 0xa1,
    OPERATOR_ADD_SINGLE = 0xa2,
    OPERATOR_ADD_DOUBLE = 0xa3,
    OPERATOR_ADD_STRING = 0xa4,
    OPERATOR_MULTIPLY_INTEGER = 0xa5,
    OPERATOR_MULTIPLY_LONG = 0xa6,
    OPERATOR_MULTIPLY_SINGLE = 0xa7,
    OPERATOR_MULTIPLY_DOUBLE = 0xa8,
    OPERATOR_FDIVIDE_INTEGER = 0xa9,
    OPERATOR_FDIVIDE_LONG = 0xaa,
    OPERATOR_FDIVIDE_SINGLE = 0xab,
    OPERATOR_FDIVIDE_DOUBLE = 0xac,
    OPERATOR_IDIVIDE_INTEGER = 0xad,
    OPERATOR_IDIVIDE_LONG = 0xae,
    OPERATOR_IDIVIDE_SINGLE = 0xaf,
    OPERATOR_IDIVIDE_DOUBLE = 0xb0,
    OPERATOR_SUBTRACT_INTEGER = 0xb1,
    OPERATOR_SUBTRACT_LONG = 0xb2,
    OPERATOR_SUBTRACT_SINGLE = 0xb3,
    OPERATOR_SUBTRACT_DOUBLE = 0xb4,
    OPERATOR_NEGATE_INTEGER = 0xb5,
    OPERATOR_NEGATE_LONG = 0xb6,
    OPERATOR_NEGATE_SINGLE = 0xb7,
    OPERATOR_NEGATE_DOUBLE = 0xb8,
    OPERATOR_EQ_INTEGER = 0xb9,
    OPERATOR_EQ_LONG = 0xba,
    OPERATOR_EQ_SINGLE = 0xbb,
    OPERATOR_EQ_DOUBLE = 0xbc,
    OPERATOR_EQ_STRING = 0xbd,
    OPERATOR_NEQ_INTEGER = 0xbe,
    OPERATOR_NEQ_LONG = 0xbf,
    OPERATOR_NEQ_SINGLE = 0xc0,
    OPERATOR_NEQ_DOUBLE = 0xc1,
    OPERATOR_NEQ_STRING = 0xc2,
    OPERATOR_LT_INTEGER = 0xc3,
    OPERATOR_LT_LONG = 0xc4,
    OPERATOR_LT_SINGLE = 0xc5,
    OPERATOR_LT_DOUBLE = 0xc6,
    OPERATOR_LT_STRING = 0xc7,
    OPERATOR_GT_INTEGER = 0xc8,
    OPERATOR_GT_LONG = 0xc9,
    OPERATOR_GT_SINGLE = 0xca,
    OPERATOR_GT_DOUBLE = 0xcb,
    OPERATOR_GT_STRING = 0xcc,
    OPERATOR_LTE_INTEGER = 0xcd,
    OPERATOR_LTE_LONG = 0xce,
    OPERATOR_LTE_SINGLE = 0xcf,
    OPERATOR_LTE_DOUBLE = 0xd0,
    OPERATOR_LTE_STRING = 0xd1,
    OPERATOR_GTE_INTEGER = 0xd2,
    OPERATOR_GTE_LONG = 0xd3,
    OPERATOR_GTE_SINGLE = 0xd4,
    OPERATOR_GTE_DOUBLE = 0xd5,
    OPERATOR_GTE_STRING = 0xd6,
    OPERATOR_AND_INTEGER = 0xd7,
    OPERATOR_AND_LONG = 0xd8,
    OPERATOR_AND_SINGLE = 0xd9,
    OPERATOR_AND_DOUBLE = 0xda,
    OPERATOR_OR_INTEGER = 0xdb,
    OPERATOR_OR_LONG = 0xdc,
    OPERATOR_OR_SINGLE = 0xdd,
    OPERATOR_OR_DOUBLE = 0xde,
    OPERATOR_XOR_INTEGER = 0xdf,
    OPERATOR_XOR_LONG = 0xe0,
    OPERATOR_XOR_SINGLE = 0xe1,
    OPERATOR_XOR_DOUBLE = 0xe2,
    PRAGMA_PRINTED = 0xfe,
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
        Opcode => try writer.writeByte(@intFromEnum(e)),
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
        u8, comptime_int => try writer.writeByte(e),
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

test "assembles" {
    const code = try assemble(testing.allocator, .{
        Opcode.PUSH_IMM_INTEGER,
        Value{ .integer = 0x7fff },
    });
    defer testing.allocator.free(code);
    try testing.expectEqualSlices(u8, "\x01\xff\x7f", code);
}
