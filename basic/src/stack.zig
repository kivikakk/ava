const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Opcode = enum(u8) {
    PUSH_IMM_INTEGER = 0x01,
    BUILTIN_PRINT = 0x02,
};

const Value = union(enum) {
    integer: i16,
};

fn assemble(comptime inp: anytype) []const u8 {
    comptime var out: []const u8 = "";
    inline for (inp) |e| {
        switch (@TypeOf(e)) {
            Opcode => out = out ++ [_]u8{@intFromEnum(e)},
            Value => {
                comptime var b: [2]u8 = undefined;
                std.mem.writeInt(i16, &b, e.integer, .little);
                out = out ++ b;
            },
            comptime_int => out = out ++ [_]u8{@as(u8, e)},
            else => @panic("unhandled type: " ++ @typeName(@TypeOf(e))),
        }
    }
    return out;
}

const TestEffects = struct {
    const Self = @This();

    printed: std.ArrayListUnmanaged(u8) = .{},

    pub fn init() !*Self {
        const self = try testing.allocator.create(Self);
        self.* = .{};
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.printed.deinit(testing.allocator);
        testing.allocator.destroy(self);
    }

    pub fn print(self: *Self, vx: []const Value) !void {
        for (vx) |v| {
            switch (v) {
                .integer => |i| try std.fmt.format(self.printed.writer(testing.allocator), "{d}", .{i}),
            }
        }
    }

    pub fn expectPrinted(self: *Self, s: []const u8) !void {
        try testing.expectEqualStrings(s, self.printed.items);
        self.printed.items.len = 0;
    }
};

fn Machine(comptime Effects: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        stack: std.ArrayListUnmanaged(Value) = .{},
        effects: Effects,

        fn init(allocator: Allocator, effects: Effects) Self {
            return .{
                .allocator = allocator,
                .effects = effects,
            };
        }

        fn deinit(self: *Self) void {
            self.stack.deinit(self.allocator);
            self.effects.deinit();
        }

        fn run(self: *Self, code: []const u8) !void {
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
    try m.effects.expectPrinted("123");
}
