const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const isa = @import("isa.zig");
const compile = @import("compile.zig");

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
            self.freeValues(self.stack.items);
            self.stack.deinit(self.allocator);
            self.effects.deinit();
        }

        fn freeValues(self: *Self, vx: []isa.Value) void {
            for (vx) |v| self.freeValue(v);
        }

        fn freeValue(self: *Self, v: isa.Value) void {
            switch (v) {
                .integer => {},
                .string => |s| self.allocator.free(s),
            }
        }

        fn takeStack(self: *Self, n: usize) []isa.Value {
            std.debug.assert(self.stack.items.len >= n);
            defer self.stack.items.len -= n;
            return self.stack.items[self.stack.items.len - n ..];
        }

        pub fn run(self: *Self, code: []const u8) !void {
            var i: usize = 0;
            while (i < code.len) {
                const b = code[i];
                const op = @as(isa.Opcode, @enumFromInt(b));
                i += 1;
                switch (op) {
                    // TOOD: a lot of these things assume they work on INTEGERs only.
                    .PUSH_IMM_INTEGER => {
                        std.debug.assert(code.len - i + 1 >= 2);
                        const imm = code[i..][0..2];
                        i += 2;
                        try self.stack.append(
                            self.allocator,
                            .{ .integer = std.mem.readInt(i16, imm, .little) },
                        );
                    },
                    .PUSH_IMM_STRING => {
                        std.debug.assert(code.len - i + 1 >= 2);
                        const lenb = code[i..][0..2];
                        i += 2;
                        const len = std.mem.readInt(u16, lenb, .little);
                        const str = code[i..][0..len];
                        i += len;
                        try self.stack.append(
                            self.allocator,
                            .{ .string = try self.allocator.dupe(u8, str) },
                        );
                    },
                    .BUILTIN_PRINT => {
                        const val = self.takeStack(1);
                        defer self.freeValues(val);
                        try self.effects.print(val[0]);
                    },
                    .BUILTIN_PRINT_COMMA => try self.effects.printComma(),
                    .BUILTIN_PRINT_LINEFEED => try self.effects.printLinefeed(),
                    .OPERATOR_ADD => {
                        std.debug.assert(self.stack.items.len >= 2);
                        const vals = self.takeStack(2);
                        const lhs = vals[0].integer;
                        const rhs = vals[1].integer;
                        try self.stack.append(self.allocator, .{ .integer = lhs + rhs });
                    },
                    .OPERATOR_MULTIPLY => {
                        std.debug.assert(self.stack.items.len >= 2);
                        const vals = self.takeStack(2);
                        const lhs = vals[0].integer;
                        const rhs = vals[1].integer;
                        try self.stack.append(self.allocator, .{ .integer = lhs * rhs });
                    },
                    .OPERATOR_NEGATE => {
                        std.debug.assert(self.stack.items.len >= 1);
                        const val = self.takeStack(1);
                        defer self.freeValues(val);
                        try self.stack.append(self.allocator, .{ .integer = -val[0].integer });
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

const TestEffects = struct {
    const Self = @This();
    const PrintedWriter = std.io.GenericWriter(*Self, Allocator.Error, writerFn);

    col: usize = 1,
    printed: std.ArrayListUnmanaged(u8),
    printedwr: PrintedWriter,

    pub fn init() !*Self {
        const self = try testing.allocator.create(Self);
        self.* = .{
            .printed = .{},
            .printedwr = PrintedWriter{ .context = self },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.printed.deinit(testing.allocator);
        testing.allocator.destroy(self);
    }

    fn writerFn(self: *Self, m: []const u8) Allocator.Error!usize {
        for (m) |c| {
            if (c == '\n') {
                self.col = 1;
            } else {
                self.col += 1;
                if (self.col == 81)
                    self.col = 1;
            }
        }
        try self.printed.appendSlice(testing.allocator, m);
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.printFormat(self.printedwr, v);
    }

    pub fn printComma(self: *Self) !void {
        // QBASIC splits the textmode screen up into 14 character "print zones".
        // Comma advances to the next, ensuring at least one space is included.
        // i.e. print zones start at column 1, 15, 29, 43, 57, 71.
        // If you're at columns 1-13 and print a comma, you'll wind up at column
        // 15. Columns 14-27 advance to 29. (14 included because 14 advancing to
        // 15 wouldn't leave a space.)
        // Why do arithmetic when just writing it out will do?
        // TODO: this won't hold up for wider screens :)
        const spaces =
            if (self.col < 14)
            15 - self.col
        else if (self.col < 28)
            29 - self.col
        else if (self.col < 42)
            43 - self.col
        else if (self.col < 56)
            57 - self.col
        else if (self.col < 70)
            71 - self.col
        else {
            try self.printedwr.writeByte('\n');
            return;
        };

        try self.printedwr.writeByteNTimes(' ', spaces);
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.printedwr.writeByte('\n');
    }

    pub fn expectPrinted(self: *Self, s: []const u8) !void {
        try testing.expectEqualStrings(s, self.printed.items);
    }
};

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
    try m.expectStack(&.{});

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
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
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

    try m.effects.expectPrinted("7\n");
}

fn testout(comptime path: []const u8, expected: []const u8) !void {
    const inp = @embedFile("testout/" ++ path);

    var m = try testRunBas(inp);
    defer m.deinit();

    try m.effects.expectPrinted(expected);
}

test "testout" {
    try testout("printzones.bas",
    //    123456789012345678901234567890
        \\a             b             c
        \\ 1 -2  3 
    );
}
