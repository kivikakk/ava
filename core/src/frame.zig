const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub fn write(comptime T: type, writer: anytype, t: T) @TypeOf(writer).Error!void {
    const len = serializeLength(T, t);
    std.debug.assert(len <= std.math.maxInt(u16));
    try writer.writeInt(u16, @intCast(len), .little);
    return try serialize(T, writer, t);
}

pub fn read(comptime T: type, allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!T {
    const len = try reader.readInt(u16, .little);
    std.debug.assert(len > 0);

    // TODO: we could just drop the frame bound, since we're going to be reading
    // from a buffer anyway (and therefore retrying isn't fraught).
    const frame = try allocator.alloc(u8, len);
    defer allocator.free(frame);
    try reader.readNoEof(frame);

    var fb = std.io.fixedBufferStream(frame);
    return try deserialize(T, allocator, fb.reader());
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
                    return try serialize(Payload, writer, @field(payload, @tagName(tag)));
                }
            }
            std.debug.panic("unmatched union tag: {x:0>2}", .{@intFromEnum(payload)});
        },
        .Enum => |e| try serialize(e.tag_type, writer, @intFromEnum(payload)),
        .Int => |_| try writer.writeInt(T, payload, .little),
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            try serialize(u32, writer, @intCast(payload.len));
            try writer.writeAll(payload);
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            inline for (s.fields) |f|
                try serialize(f.type, writer, @field(payload, f.name));
        },
        .Bool => try writer.writeByte(@intFromBool(payload)),
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
        .Enum => |e| return serializeLength(e.tag_type, @intFromEnum(payload)),
        .Int => |i| return @divExact(i.bits, 8),
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            return serializeLength(u32, @intCast(payload.len)) + payload.len;
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            var len: usize = 0;
            inline for (s.fields) |f|
                len += serializeLength(f.type, @field(payload, f.name));
            return len;
        },
        .Bool => return 1,
        .Void => return 0,
        else => @compileError("unhandled type: " ++ @typeName(T) ++ " (" ++ @tagName(@typeInfo(T)) ++ ")"),
    }
}

fn deserialize(comptime T: type, allocator: Allocator, reader: anytype) (Allocator.Error || @TypeOf(reader).NoEofError)!T {
    switch (@typeInfo(T)) {
        .Union => |u| {
            comptime std.debug.assert(u.tag_type != null);
            const Tag = u.tag_type.?;
            const kind = try deserialize(Tag, allocator, reader);
            inline for (comptime std.meta.tags(Tag)) |tag| {
                if (kind == tag) {
                    const Payload = std.meta.TagPayload(T, tag);
                    const payload = try deserialize(Payload, allocator, reader);
                    return @unionInit(T, @tagName(tag), payload);
                }
            }
            std.debug.panic("unmatched union tag: {x:0>2}", .{@intFromEnum(kind)});
        },
        .Enum => |e| return @enumFromInt(try deserialize(e.tag_type, allocator, reader)),
        .Int => |_| return try reader.readInt(T, .little),
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            const len = try deserialize(u32, allocator, reader);
            const a = try allocator.alloc(u8, len);
            try reader.readNoEof(a);
            return a;
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            var r: T = undefined;
            inline for (s.fields) |f|
                @field(r, f.name) = try deserialize(f.type, allocator, reader);
            return r;
        },
        .Bool => return try reader.readByte() == 1,
        .Void => return,
        else => @compileError("unhandled type: " ++ @typeName(T) ++ " (" ++ @tagName(@typeInfo(T)) ++ ")"),
    }
}

pub fn free(comptime T: type, allocator: Allocator, t: T) void {
    switch (@typeInfo(T)) {
        .Union => |u| {
            comptime std.debug.assert(u.tag_type != null);
            const Tag = u.tag_type.?;
            inline for (comptime std.meta.tags(Tag)) |tag| {
                if (t == tag) {
                    const Payload = std.meta.TagPayload(T, tag);
                    return free(Payload, allocator, @field(t, @tagName(tag)));
                }
            }
            std.debug.panic("unmatched union tag: {x:0>2}", .{@intFromEnum(t)});
        },
        .Enum => {},
        .Int => {},
        .Pointer => |p| {
            comptime std.debug.assert(p.size == .Slice);
            comptime std.debug.assert(p.sentinel == null);
            comptime std.debug.assert(p.child == u8); // XXX
            allocator.free(t);
        },
        .Struct => |s| {
            comptime std.debug.assert(s.layout == .auto);
            inline for (s.fields) |f|
                free(f.type, allocator, @field(t, f.name));
        },
        .Bool => {},
        .Void => {},
        else => @compileError("unhandled type: " ++ @typeName(T) ++ " (" ++ @tagName(@typeInfo(T)) ++ ")"),
    }
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

fn expectDeserialize(comptime T: type, inp: []const u8, exp: T) !void {
    var fb = std.io.fixedBufferStream(inp);

    const t = try deserialize(T, testing.allocator, fb.reader());
    defer free(T, testing.allocator, t);
    try testing.expectEqualDeep(exp, t);
}

test "deserializing" {
    try expectDeserialize(u16, "\xcd\xab", 0xabcd);
    try expectDeserialize(TestEnum, "\x02", .B);
    try expectDeserialize([]const u8, "\x09\x00\x00\x00Awawa :)\n", "Awawa :)\n");
    try expectDeserialize(TestUnion, "\x01", .A);
    try expectDeserialize(TestUnion, "\x02\x03\x00\x00\x00^_^", .{ .B = "^_^" });
    try expectDeserialize(TestUnion, "\x03\x7f\x02\x00\x00\x00\xff\xff\x00", .{ .C = .{ .x = 127, .y = "\xff\xff", .z = .{ .m = false } } });
}
