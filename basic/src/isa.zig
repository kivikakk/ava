const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Opcode = enum(u8) {
    PUSH_IMM_INTEGER = 0x01,
    PUSH_IMM_STRING = 0x02,
    PUSH_VARIABLE = 0x0a,
    LET = 0x10,
    BUILTIN_PRINT = 0x80,
    BUILTIN_PRINT_COMMA = 0x81,
    BUILTIN_PRINT_LINEFEED = 0x82,
    OPERATOR_ADD = 0xd0,
    OPERATOR_MULTIPLY = 0xd1,
    OPERATOR_NEGATE = 0xd2,
};

pub const Value = union(enum) {
    const Self = @This();

    integer: i16,
    string: []const u8,

    pub fn clone(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .integer => self,
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
        };
    }
};

pub fn printFormat(writer: anytype, v: Value) !void {
    switch (v) {
        .integer => |i| {
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
