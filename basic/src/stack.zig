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
            else => @panic("unhandled type: " ++ @typeName(@TypeOf(e))),
        }
    }
    return out;
}

const Machine = struct {
    const Self = @This();

    allocator: Allocator,
    stack: std.ArrayListUnmanaged(Value) = .{},

    fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
    }

    fn run(self: *Self, code: []const u8) !void {
        var i: usize = 0;
        while (i < code.len) : (i += 1) {
            const b = code[i];
            switch (@as(Opcode, @enumFromInt(b))) {
                .PUSH_IMM_INTEGER => {
                    std.debug.assert(code.len - i - 1 >= 2);
                    try self.stack.append(
                        self.allocator,
                        .{ .integer = std.mem.readInt(i16, code[i + 1 ..][0..2], .little) },
                    );
                    i += 2;
                },
                else => unreachable,
            }
        }
    }

    fn expectStack(self: *const Self, stack: []const Value) !void {
        try testing.expectEqualSlices(Value, stack, self.stack.items);
    }
};

test "simple push and asseble" {
    var m = Machine.init(testing.allocator);
    defer m.deinit();

    const code = assemble(.{
        Opcode.PUSH_IMM_INTEGER,
        Value{ .integer = 0x7fff },
    });
    try testing.expectEqualSlices(u8, "\x01\xff\x7f", code);
    try m.run(code);
    try m.expectStack(&.{.{ .integer = 0x7fff }});
}
