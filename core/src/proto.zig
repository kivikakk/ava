const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const frame = @import("./frame.zig");

pub const RequestTag = enum(u8) {
    HELLO = 0x01,
    MACHINE_INIT = 0x02,
    MACHINE_EXEC = 0x03,
    EXIT = 0xfe,
};

pub const Request = union(RequestTag) {
    const Self = @This();

    HELLO,
    MACHINE_INIT,
    MACHINE_EXEC: []const u8,
    EXIT,

    pub fn deinit(self: Self, allocator: Allocator) void {
        frame.free(Self, allocator, self);
    }

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        try frame.write(Self, writer, self);
    }

    pub fn read(allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!Self {
        return frame.read(Self, allocator, reader);
    }
};

pub const EventTag = enum(u8) {
    OK = 0x01,
    VERSION = 0x02,
    DEBUG = 0x03,
    INVALID = 0x04,
    ERROR = 0xfe,
};

pub const Event = union(EventTag) {
    const Self = @This();

    OK,
    VERSION: []const u8,
    DEBUG: []const u8,
    INVALID,
    ERROR: []const u8,

    pub fn deinit(self: Self, allocator: Allocator) void {
        frame.free(Self, allocator, self);
    }

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        try frame.write(Self, writer, self);
    }

    pub fn read(allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!Self {
        return frame.read(Self, allocator, reader);
    }
};

fn expectRoundtrip(comptime T: type, inp: T) !void {
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try inp.write(buf.writer());
    var fb = std.io.fixedBufferStream(buf.items);
    const out = try T.read(testing.allocator, fb.reader());
    defer out.deinit(testing.allocator);

    try testing.expectEqualDeep(inp, out);
}

test "roundtrips" {
    try expectRoundtrip(Request, .HELLO);
    try expectRoundtrip(Request, .{ .MACHINE_EXEC = "\xaa\xbb\xcc" });
    try expectRoundtrip(Event, .OK);
    try expectRoundtrip(Event, .{ .VERSION = "xyzzy 123!" });
}
