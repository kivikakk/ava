const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

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
    OPERATOR_ADD_INTEGER = 0xd0,
    OPERATOR_ADD_LONG = 0xd1,
    OPERATOR_ADD_SINGLE = 0xd2,
    OPERATOR_ADD_DOUBLE = 0xd3,
    OPERATOR_ADD_STRING = 0xd4,
    OPERATOR_MULTIPLY_INTEGER = 0xd5,
    OPERATOR_MULTIPLY_LONG = 0xd6,
    OPERATOR_MULTIPLY_SINGLE = 0xd7,
    OPERATOR_MULTIPLY_DOUBLE = 0xd8,
    OPERATOR_SUBTRACT_INTEGER = 0xd9,
    OPERATOR_SUBTRACT_LONG = 0xda,
    OPERATOR_SUBTRACT_SINGLE = 0xdb,
    OPERATOR_SUBTRACT_DOUBLE = 0xdc,
    OPERATOR_DIVIDE_INTEGER = 0xde,
    OPERATOR_DIVIDE_LONG = 0xdf,
    OPERATOR_DIVIDE_SINGLE = 0xe0,
    OPERATOR_DIVIDE_DOUBLE = 0xe1,
    OPERATOR_NEGATE_INTEGER = 0xe2,
    OPERATOR_NEGATE_LONG = 0xe3,
    OPERATOR_NEGATE_SINGLE = 0xe4,
    OPERATOR_NEGATE_DOUBLE = 0xe5,
};

pub const Value = union(enum) {
    const Self = @This();

    integer: i16,
    long: i32,
    string: []const u8,

    pub fn clone(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .integer, .long => self,
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
        };
    }
};

pub fn printFormat(writer: anytype, v: Value) !void {
    switch (v) {
        .integer, .long => |i| {
            if (i >= 0)
                try writer.writeByte(' ');
            try std.fmt.format(writer, "{d} ", .{i});
        },
        .string => |s| try writer.writeAll(s),
    }
}

pub fn assembleOne(e: anytype, writer: anytype) !void {
    switch (@TypeOf(e)) {
        Opcode => try writer.writeByte(@intFromEnum(e)),
        Value => {
            switch (e) {
                .integer => |i| try writer.writeInt(i16, i, .little),
                .long => |i| try writer.writeInt(i32, i, .little),
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
