const std = @import("std");
const testing = std.testing;

pub const RequestKind = enum(u8) {
    HELLO = 0x01,
};

pub const Request = union(RequestKind) {
    const Self = @This();

    HELLO: void,

    pub fn read(reader: anytype) @TypeOf(reader).Error!Self {
        const c = try reader.readByte();

        switch (@as(RequestKind, @enumFromInt(c))) {
            .HELLO => return .HELLO,
        }
    }

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeByte(@intFromEnum(self));
    }
};

pub const Response = union(RequestKind) {
    const Self = @This();

    HELLO: []const u8,

    pub fn write(self: Self, writer: anytype) @TypeOf(writer).Error!void {
        try writer.writeByte(@intFromEnum(self));

        switch (self) {
            .HELLO => |id| {
                try writer.writeByte(@intCast(id.len));
                try writer.writeAll(id);
            },
        }
    }
};

fn expectRoundtrips(inp: anytype) !void {
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try inp.write(buf.writer());
    var fbs = std.io.fixedBufferStream(buf.items);
    const out = try @TypeOf(inp).read(fbs.reader());

    try testing.expectEqualDeep(inp, out);
}

test "request roundtrips" {
    try expectRoundtrips(Request{ .HELLO = {} });
    try expectRoundtrips(Response{ .HELLO = "xyzzy 123!" });
}
