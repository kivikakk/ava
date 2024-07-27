const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const isa = @import("isa.zig");
const compile = @import("compile.zig");

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

    pub fn print(self: *Self, vx: []const isa.Value) !void {
        try isa.printFormat(self.printedwr, vx);
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
        stack: std.ArrayListUnmanaged(isa.Value) = .{},
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
            while (i < code.len) {
                const b = code[i];
                const op = @as(isa.Opcode, @enumFromInt(b));
                i += 1;
                switch (op) {
                    .PUSH_IMM_INTEGER => {
                        std.debug.assert(code.len - i + 1 >= 2);
                        const imm = code[i..][0..2];
                        i += 2;
                        try self.stack.append(
                            self.allocator,
                            .{ .integer = std.mem.readInt(i16, imm, .little) },
                        );
                    },
                    .BUILTIN_PRINT => {
                        std.debug.assert(code.len - i + 1 >= 1);
                        const argc = code[i];
                        i += 1;
                        std.debug.assert(self.stack.items.len >= argc);
                        try self.effects.print(self.stack.items[self.stack.items.len - argc ..]);
                        self.stack.items.len -= argc;
                    },
                    .OPERATOR_ADD => {
                        std.debug.assert(code.len - i + 1 >= 0);
                        std.debug.assert(self.stack.items.len >= 2);
                        const vals = self.stack.items[self.stack.items.len - 2 ..];
                        self.stack.items.len -= 2;
                        const lhs = vals[0].integer;
                        const rhs = vals[1].integer;
                        try self.stack.append(self.allocator, .{ .integer = lhs + rhs });
                    },
                    .OPERATOR_MULTIPLY => {
                        std.debug.assert(code.len - i + 1 >= 0);
                        std.debug.assert(self.stack.items.len >= 2);
                        const vals = self.stack.items[self.stack.items.len - 2 ..];
                        self.stack.items.len -= 2;
                        const lhs = vals[0].integer;
                        const rhs = vals[1].integer;
                        try self.stack.append(self.allocator, .{ .integer = lhs * rhs });
                    },
                    else => std.debug.panic("unhandled opcode: {s}", .{@tagName(op)}),
                }
            }
        }

        fn expectStack(self: *const Self, vx: []const isa.Value) !void {
            try testing.expectEqualSlices(isa.Value, vx, self.stack.items);
        }
    };
}

fn testRun(inp: anytype) !Machine(*TestEffects) {
    const code = try isa.assemble(testing.allocator, inp);
    defer testing.allocator.free(code);

    var m = Machine(*TestEffects).init(testing.allocator, try TestEffects.init());
    errdefer m.deinit();

    try m.run(code);
    return m;
}

fn testRunBas(inp: []const u8) !Machine(*TestEffects) {
    const code = try compile.compile(testing.allocator, inp, null);
    defer testing.allocator.free(code);

    var m = Machine(*TestEffects).init(testing.allocator, try TestEffects.init());
    errdefer m.deinit();

    try m.run(code);
    return m;
}

test "simple push" {
    var m = try testRun(.{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 0x7fff },
    });
    defer m.deinit();

    try m.expectStack(&.{.{ .integer = 0x7fff }});
}

test "actually print a thing" {
    var m = try testRun(.{
        isa.Opcode.PUSH_IMM_INTEGER,
        isa.Value{ .integer = 123 },
        isa.Opcode.BUILTIN_PRINT,
        1,
    });
    defer m.deinit();

    try m.expectStack(&.{});
    try m.effects.expectPrinted("123\n");
}

test "actually print a calculated thing" {
    var m = try testRunBas(
        \\PRINT 1 + 2 * 3
        \\
    );
    defer m.deinit();

    try m.expectStack(&.{});
    try m.effects.expectPrinted("7\n");
}
