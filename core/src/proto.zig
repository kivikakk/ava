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
        const len = serializeLength(Self, self);
        std.debug.assert(len <= std.math.maxInt(u16));
        try writer.writeInt(u16, @intCast(len), .little);
        try serialize(Self, writer, self);
    }

    pub fn read(allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!Self {
        const frame = try readFrame(allocator, reader);
        defer allocator.free(frame);

        var fb = std.io.fixedBufferStream(frame);
        return try deserialize(Self, allocator, fb.reader());
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

fn readFrame(allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)![]u8 {
    const len = try reader.readInt(u16, .little);
    std.debug.assert(len > 0);
    const frame = try allocator.alloc(u8, len);
    errdefer allocator.free(frame);
    try reader.readNoEof(frame);
    return frame;
}

fn serialize(comptime T: type, writer: anytype, payload: T) @TypeOf(writer).Error!void {
    switch (@typeInfo(T)) {
        .Union => |u| {
            comptime std.debug.assert(u.tag_type != null);
            const Tag = u.tag_type.?;
            try serialize(Tag, writer, payload);
            inline for (comptime std.meta.tags(Tag)) |tag| {
                if (payload == tag) {
                    const Payload = std.meta.TagPayload(T, tag);
                    try serialize(Payload, writer, @field(payload, @tagName(tag)));
                    return;
                }
            }
            std.debug.panic("unmatched union tag: {x:0>2}", .{@intFromEnum(payload)});
        },
        .Enum => |e| {
            try serialize(e.tag_type, writer, @intFromEnum(payload));
        },
        .Int => |_| {
            try writer.writeInt(T, payload, .little);
        },
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            try serialize(u32, writer, @intCast(payload.len));
            try writer.writeAll(payload);
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            inline for (s.fields) |f| {
                try serialize(f.type, writer, @field(payload, f.name));
            }
        },
        .Bool => {
            try writer.writeByte(@intFromBool(payload));
        },
        .Void => {},
        else => @compileError("unhandled type: " ++ @typeName(T) ++ " (" ++ @tagName(@typeInfo(T)) ++ ")"),
    }
}

fn serializeLength(comptime T: type, payload: T) usize {
    switch (@typeInfo(T)) {
        .Union => |u| {
            comptime std.debug.assert(u.tag_type != null);
            const Tag = u.tag_type.?;
            inline for (comptime std.meta.tags(Tag)) |tag| {
                if (payload == tag) {
                    const Payload = std.meta.TagPayload(T, tag);
                    return serializeLength(Tag, payload) + serializeLength(Payload, @field(payload, @tagName(tag)));
                }
            }
            std.debug.panic("unmatched union tag: {x:0>2}", .{@intFromEnum(payload)});
        },
        .Enum => |e| {
            return serializeLength(e.tag_type, @intFromEnum(payload));
        },
        .Int => |i| {
            return @divExact(i.bits, 8);
        },
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            return serializeLength(u32, @intCast(payload.len)) + payload.len;
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            var len: usize = 0;
            inline for (s.fields) |f| {
                len += serializeLength(f.type, @field(payload, f.name));
            }
            return len;
        },
        .Bool => return 1,
        .Void => return 0,
        else => @compileError("unhandled type: " ++ @typeName(T) ++ " (" ++ @tagName(@typeInfo(T)) ++ ")"),
    }
}

fn deserialize(comptime T: type, allocator: Allocator, reader: anytype) Allocator.Error!T {
    _ = allocator;
    _ = reader;

    // const kind = @as(RequestKind, @enumFromInt(try fbr.readByte()));
    // inline for (comptime std.meta.tags(RequestKind)) |tag| {
    //     if (kind == tag) {
    //         const Payload = std.meta.TagPayload(Request, tag);
    //         var r: Payload = undefined;
    //         try deserialize(Payload, allocator, fbr, &r);
    //         return @unionInit(Request, @tagName(tag), r);
    //     }
    // }
    // std.debug.panic("unmatched request tag: {x:0>2}", .{@intFromEnum(kind)});
    unreachable;
}

const TestEnum = enum(u8) {
    A = 0x01,
    B = 0x02,
    C = 0x03,
};

const TestUnion = union(TestEnum) {
    A: void,
    B: []const u8,
    C: struct { x: i8, y: []const u8, z: struct { m: bool } },
};

fn expectSerialize(comptime T: type, t: T, exp: []const u8) !void {
    const len = serializeLength(T, t);
    try testing.expectEqual(exp.len, len);

    var a = std.ArrayList(u8).init(testing.allocator);
    defer a.deinit();
    try serialize(T, a.writer(), t);
    try testing.expectEqualStrings(exp, a.items);
}

test "serializing" {
    try expectSerialize(u16, 0x1234, "\x34\x12");
    try expectSerialize(TestEnum, .B, "\x02");
    try expectSerialize([]const u8, "head sõbrad!", "\x0d\x00\x00\x00head s\xc3\xb5brad!");
    try expectSerialize(TestUnion, .A, "\x01");
    try expectSerialize(TestUnion, .{ .B = "abacus" }, "\x02\x06\x00\x00\x00abacus");
    try expectSerialize(TestUnion, .{ .C = .{ .x = -128, .y = "", .z = .{ .m = true } } }, "\x03\x80\x00\x00\x00\x00\x01");
}

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

// test "request roundtrips" {
//     try expectRoundtripRequest(.HELLO);
//     try expectRoundtripRequest(.{ .MACHINE_INIT = "\xaa\xbb\xcc" });
//     try expectRoundtripResponse(.{ .HELLO = "xyzzy 123!" });
//     try expectRoundtripResponse(.MACHINE_INIT);
// }
