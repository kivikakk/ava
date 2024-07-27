const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Opcode = enum(u8) {
    PUSH_IMM_INTEGER = 0x01,
    BUILTIN_PRINT = 0x02,
};

pub const Value = union(enum) {
    integer: i16,
};

pub fn assembleOne(e: anytype, out: *[3]u8) usize {
    switch (@TypeOf(e)) {
        Opcode => {
            out[0] = @intFromEnum(e);
            return 1;
        },
        Value => {
            std.mem.writeInt(i16, &out[0..2].*, e.integer, .little);
            return 2;
        },
        u8, comptime_int => {
            out[0] = @as(u8, e);
            return 1;
        },
        else => @panic("unhandled type: " ++ @typeName(@TypeOf(e))),
    }
}

pub fn assemble(comptime inp: anytype) []const u8 {
    comptime var out: []const u8 = "";
    comptime var buf: [3]u8 = undefined;
    inline for (inp) |e| {
        const len = comptime assembleOne(e, &buf);
        out = out ++ buf[0..len];
    }
    return out;
}

pub fn assembleInto(inp: anytype, writer: anytype) !void {
    var buf: [3]u8 = undefined;
    inline for (inp) |e| {
        const len = assembleOne(e, &buf);
        try writer.writeAll(buf[0..len]);
    }
}

pub fn printFormat(writer: anytype, vx: []const Value) !void {
    for (vx) |v| {
        switch (v) {
            .integer => |i| try std.fmt.format(writer, "{d}", .{i}),
        }
    }
    try writer.writeByte('\n');
}

const TestEffects = struct {
    const Self = @This();

    printed: std.ArrayListUnmanaged(u8) = .{},
    printedwr: std.ArrayListUnmanaged(u8).Writer,

    pub fn init() !*Self {
        const self = try testing.allocator.create(Self);
        self.* = .{ .printedwr = undefined };
        self.printedwr = self.printed.writer(testing.allocator);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.printed.deinit(testing.allocator);
        testing.allocator.destroy(self);
    }

    pub fn print(self: *Self, vx: []const Value) !void {
        try printFormat(self.printedwr, vx);
    }

    pub fn expectPrinted(self: *Self, s: []const u8) !void {
        try testing.expectEqualStrings(s, self.printed.items);
        self.printed.items.len = 0;
    }
};

pub fn Machine(comptime Effects: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        stack: std.ArrayListUnmanaged(Value) = .{},
        effects: Effects,

        pub fn init(allocator: Allocator, effects: Effects) Self {
            return .{
                .allocator = allocator,
                .effects = effects,
            };
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit(self.allocator);
            self.effects.deinit();
        }

        pub fn run(self: *Self, code: []const u8) !void {
            var i: usize = 0;
            while (i < code.len) : (i += 1) {
                const b = code[i];
                const op = @as(Opcode, @enumFromInt(b));
                switch (op) {
                    .PUSH_IMM_INTEGER => {
                        std.debug.assert(code.len - i - 1 >= 2);
                        try self.stack.append(
                            self.allocator,
                            .{ .integer = std.mem.readInt(i16, code[i + 1 ..][0..2], .little) },
                        );
                        i += 2;
                    },
                    .BUILTIN_PRINT => {
                        std.debug.assert(code.len - i - 1 >= 1);
                        const argc = code[i + 1];
                        std.debug.assert(self.stack.items.len >= argc);
                        try self.effects.print(self.stack.items[self.stack.items.len - argc ..]);
                        self.stack.items.len -= argc;
                        i += 1;
                    },
                    // else => std.debug.panic("unhandled opcode: {s}", .{@tagName(op)}),
                }
            }
        }

        fn expectStack(self: *const Self, vx: []const Value) !void {
            try testing.expectEqualSlices(Value, vx, self.stack.items);
        }
    };
}

test "simple push and asseble" {
    var m = Machine(*TestEffects).init(testing.allocator, try TestEffects.init());
    defer m.deinit();

    const code = assemble(.{
        Opcode.PUSH_IMM_INTEGER,
        Value{ .integer = 0x7fff },
    });
    try testing.expectEqualSlices(u8, "\x01\xff\x7f", code);
    try m.run(code);
    try m.expectStack(&.{.{ .integer = 0x7fff }});
}

fn testRun(comptime inp: anytype) !Machine(*TestEffects) {
    var m = Machine(*TestEffects).init(testing.allocator, try TestEffects.init());
    errdefer m.deinit();

    try m.run(assemble(inp));
    return m;
}

test "actually print a thing" {
    var m = try testRun(.{
        Opcode.PUSH_IMM_INTEGER,
        Value{ .integer = 123 },
        Opcode.BUILTIN_PRINT,
        1,
    });
    defer m.deinit();

    try m.expectStack(&.{});
    try m.effects.expectPrinted("123\n");
}
