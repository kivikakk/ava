const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const RequestKind = enum(u8) {
    HELLO = 0x01,
    MACHINE_INIT = 0x02,
    EXIT = 0x03,
};

pub const Request = union(RequestKind) {
    const Self = @This();

    HELLO: void,
    MACHINE_INIT: []const u8,
    EXIT: void,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .HELLO => {},
            .MACHINE_INIT => |c| allocator.free(c),
            .EXIT => {},
        }
    }

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeByte(@intFromEnum(self));
        switch (self) {
            .HELLO => {},
            .MACHINE_INIT => |c| {
                try writer.writeInt(u32, @intCast(c.len), .little);
                try writer.writeAll(c);
            },
            .EXIT => {},
        }
    }

    pub fn read(allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!Self {
        const c = try reader.readByte();

        switch (@as(RequestKind, @enumFromInt(c))) {
            .HELLO => return .HELLO,
            .MACHINE_INIT => {
                const n = try reader.readInt(u32, .little);
                const buf = try allocator.alloc(u8, n);
                try reader.readNoEof(buf);
                return .{ .MACHINE_INIT = buf };
            },
            .EXIT => return .EXIT,
        }
    }
};

pub const Response = union(RequestKind) {
    const Self = @This();

    HELLO: []const u8,
    MACHINE_INIT: void,
    EXIT: void,

    pub fn deinit(allocator: Allocator, comptime kind: RequestKind, payload: std.meta.TagPayload(Response, kind)) void {
        switch (kind) {
            .HELLO => allocator.free(payload),
            .MACHINE_INIT => {},
            .EXIT => {},
        }
    }

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            .HELLO => |id| {
                try writer.writeByte(@intCast(id.len));
                try writer.writeAll(id);
            },
            .MACHINE_INIT => {
                try writer.writeByte(1);
            },
            .EXIT => {
                try writer.writeByte(0xff);
            },
        }
    }

    // Reading responses is, for now, optimised for the host-side; we assume we
    // have a lot of memory and compute, and don't want to block.
    pub fn read(allocator: Allocator, reader: anytype, comptime kind: RequestKind) (Allocator.Error || @TypeOf(reader).NoEofError)!std.meta.TagPayload(Response, kind) {
        switch (kind) {
            .HELLO => {
                const len = try reader.readByte();
                const buf = try allocator.alloc(u8, len);
                errdefer allocator.free(buf);
                try reader.readNoEof(buf);
                return buf;
            },
            .MACHINE_INIT => {
                std.debug.assert(try reader.readByte() == 1);
            },
            .EXIT => {
                std.debug.assert(try reader.readByte() == 0xff);
            },
        }
    }
};

fn expectRoundtripRequest(inp: Request) !void {
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try inp.write(buf.writer());
    var fbs = std.io.fixedBufferStream(buf.items);
    const out = try Request.read(testing.allocator, fbs.reader());
    defer out.deinit(testing.allocator);

    try testing.expectEqualDeep(inp, out);
}

fn expectRoundtripResponse(comptime inp: Response) !void {
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try inp.write(buf.writer());
    var fbs = std.io.fixedBufferStream(buf.items);

    const out = try Response.read(testing.allocator, fbs.reader(), inp);
    defer Response.deinit(testing.allocator, inp, out);

    try testing.expectEqualDeep(@field(inp, @tagName(inp)), out);
}

test "request roundtrips" {
    try expectRoundtripRequest(.HELLO);
    try expectRoundtripRequest(.{ .MACHINE_INIT = "\xaa\xbb\xcc" });
    try expectRoundtripResponse(.{ .HELLO = "xyzzy 123!" });
    try expectRoundtripResponse(.MACHINE_INIT);
}
