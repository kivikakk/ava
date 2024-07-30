const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const isa = @import("isa.zig");
const Compiler = @import("Compiler.zig");
const PrintLoc = @import("PrintLoc.zig");
const ErrorInfo = @import("ErrorInfo.zig");

const Error = error{
    TypeMismatch,
    Unimplemented,
};

pub fn Machine(comptime Effects: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        stack: std.ArrayListUnmanaged(isa.Value) = .{},
        effects: *Effects,
        errorinfo: ?*ErrorInfo,

        pub fn init(allocator: Allocator, effects: *Effects, errorinfo: ?*ErrorInfo) Self {
            return .{
                .allocator = allocator,
                .effects = effects,
                .errorinfo = errorinfo,
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

        pub fn run(self: *Self, code: []const u8) (Error || Allocator.Error || Effects.Error)!void {
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
                    .PUSH_IMM_STRING => {
                        std.debug.assert(code.len - i + 1 >= 2);
                        const lenb = code[i..][0..2];
                        i += 2;
                        const len = std.mem.readInt(u16, lenb, .little);
                        const str = code[i..][0..len];
                        i += len;
                        const s = try self.allocator.dupe(u8, str);
                        errdefer self.allocator.free(s);
                        try self.stack.append(self.allocator, .{ .string = s });
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
                        defer self.freeValues(vals);
                        switch (vals[0]) {
                            .integer => |lhs| {
                                const rhs = vals[1].integer;
                                try self.stack.append(self.allocator, .{ .integer = lhs + rhs });
                            },
                            else => {
                                // TODO: need locinfo from bytecode.
                                if (self.errorinfo) |ei|
                                    ei.msg = try std.fmt.allocPrint(self.allocator, "unhandled add: {s}", .{@tagName(vals[0])});
                                return Error.Unimplemented;
                            },
                        }
                    },
                    .OPERATOR_MULTIPLY => {
                        std.debug.assert(self.stack.items.len >= 2);
                        const vals = self.takeStack(2);
                        defer self.freeValues(vals);
                        switch (vals[0]) {
                            .integer => |lhs| {
                                const rhs = vals[1].integer;
                                try self.stack.append(self.allocator, .{ .integer = lhs * rhs });
                            },
                            else => std.debug.panic("unhandled multiply: {s}", .{@tagName(vals[0])}),
                        }
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
    pub const Error = error{};
    const PrintedWriter = std.io.GenericWriter(*Self, Allocator.Error, writerFn);

    printed: std.ArrayListUnmanaged(u8),
    printedwr: PrintedWriter,
    printloc: PrintLoc = .{},

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
        self.printloc.write(m);
        try self.printed.appendSlice(testing.allocator, m);
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.printFormat(self.printedwr, v);
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try self.printedwr.writeByte('\n'),
            .spaces => |s| try self.printedwr.writeByteNTimes(' ', s),
        }
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.printedwr.writeByte('\n');
    }

    pub fn expectPrinted(self: *Self, s: []const u8) !void {
        try testing.expectEqualStrings(s, self.printed.items);
    }
};

fn testRun(inp: anytype) !Machine(TestEffects) {
    const code = try isa.assemble(testing.allocator, inp);
    defer testing.allocator.free(code);

    var m = Machine(TestEffects).init(testing.allocator, try TestEffects.init(), null);
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
        isa.Opcode.BUILTIN_PRINT_LINEFEED,
    });
    defer m.deinit();

    try m.expectStack(&.{});
    try m.effects.expectPrinted(" 123 \n");
}

fn testRunBas(allocator: Allocator, inp: []const u8) !Machine(TestEffects) {
    const code = try Compiler.compile(allocator, inp, null);
    defer allocator.free(code);

    var m = Machine(TestEffects).init(allocator, try TestEffects.init(), null);
    errdefer m.deinit();

    try m.run(code);
    try m.expectStack(&.{});

    return m;
}

test "actually print a calculated thing" {
    var m = try testRunBas(testing.allocator,
        \\PRINT 1 + 2 * 3
        \\
    );
    defer m.deinit();

    try m.effects.expectPrinted(" 7 \n");
}

fn testoutInner(allocator: Allocator, inp: []const u8, expected: []const u8) !void {
    var m = try testRunBas(allocator, inp);
    defer m.deinit();

    try m.effects.expectPrinted(expected);
}

fn testout(comptime path: []const u8, expected: []const u8) !void {
    const inp = @embedFile("bas/" ++ path);
    try testing.checkAllAllocationFailures(testing.allocator, testoutInner, .{ inp, expected });
}

test "test expected program output" {
    try testout("printzones.bas",
    //    123456789012345678901234567890
        \\a             b             c
        \\ 1 -2  3 
    );
}
