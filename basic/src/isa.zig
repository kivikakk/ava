const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Opcode = enum(u8) {
    PUSH_IMM_INTEGER = 0x01,
    PUSH_IMM_STRING = 0x02,
    BUILTIN_PRINT = 0x80,
    OPERATOR_ADD = 0xd0,
    OPERATOR_MULTIPLY = 0xd1,
};

// XXX: feels complected
pub const Value = union(enum) {
    integer: i16,
    string: []const u8,
};

pub fn printFormat(writer: anytype, vx: []const Value) !void {
    for (vx) |v| {
        switch (v) {
            .integer => |i| try std.fmt.format(writer, "{d}", .{i}),
            .string => |s| try writer.writeAll(s),
        }
    }
    try writer.writeByte('\n');
}

pub fn assembleOne(e: anytype, writer: anytype) !void {
    switch (@TypeOf(e)) {
        Opcode => try writer.writeByte(@intFromEnum(e)),
        Value => {
            switch (e) {
                .integer => |i| {
                    var b: [2]u8 = undefined;
                    std.mem.writeInt(i16, &b, i, .little);
                    try writer.writeAll(&b);
                },
                .string => |s| {
                    _ = s;
                },
            }
        },
        u8, comptime_int => try writer.writeByte(e),
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
