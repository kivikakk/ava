const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const frame = @import("./frame.zig");

pub const RequestTag = enum(u8) {
    HELLO = 0x01,
    MACHINE_INIT = 0x02,
    EXIT = 0x03,
};

pub const Request = union(RequestTag) {
    const Self = @This();

    HELLO,
    MACHINE_INIT: []const u8,
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
    READY = 0x01,
    VERSION = 0x02,
    EXECUTING = 0x03,
    ERROR = 0x04,
    UART = 0x05,
};

pub const Event = union(EventTag) {
    const Self = @This();

    READY,
    VERSION: []const u8,
    EXECUTING,
    ERROR: []const u8,
    UART: []const u8,

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
    try expectRoundtrip(Request, .{ .MACHINE_INIT = "\xaa\xbb\xcc" });
    try expectRoundtrip(Event, .READY);
    try expectRoundtrip(Event, .{ .VERSION = "xyzzy 123!" });
}
