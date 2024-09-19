const std = @import("std");
const Allocator = std.mem.Allocator;

const eheap = @import("eheap");
const stack = @import("avabasic").stack;
const isa = @import("avabasic").isa;
const PrintLoc = @import("avabasic").PrintLoc;

const uart = @import("./uart.zig");
const proto = @import("./proto.zig");

const VERSION: usize = 2;
var arena: [64 * 1024]u8 align(4) = undefined;

pub fn main() !void {
    var heap: eheap.Heap(64 * 1024) = .{ .arena = arena };
    heap.initialize();
    const allocator = heap.allocator();

    var machine: ?stack.Machine(Effects) = null;
    var code: ?[]const u8 = null;

    while (true) {
        try uart.writeEvent(.READY);

        const req = uart.readRequest(allocator) catch {
            try uart.writeEvent(.{ .ERROR = "readRequest" });
            continue;
        };
        defer req.deinit(allocator);
        switch (req) {
            .HELLO => {
                try uart.writeEvent(.{ .VERSION = std.fmt.comptimePrint("AvaCore {d}", .{VERSION}) });
            },
            .MACHINE_INIT => |new_code| {
                if (machine) |*m|
                    m.deinit();
                if (code) |c|
                    allocator.free(c);

                effects = .{ .allocator = allocator };
                machine = stack.Machine(Effects).init(allocator, &effects, null);
                code = new_code;

                try uart.writeEvent(.EXECUTING);
                try machine.?.run(code.?);
            },
            .EXIT => break,
        }
    }

    try uart.writer.print("exiting main\n", .{});
}

var effects: Effects = undefined;

const Effects = struct {
    const Self = @This();

    pub const Error = error{};

    allocator: Allocator,
    printloc: PrintLoc = .{},

    pub fn deinit(_: *Self) void {}

    pub fn print(self: *Self, v: isa.Value) !void {
        var b = std.ArrayListUnmanaged(u8){};
        defer b.deinit(self.allocator);
        try isa.printFormat(self.allocator, b.writer(self.allocator), v);
        try uart.writeEvent(.{ .UART = b.items });
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try uart.writeEvent(.{ .UART = "\n" }),
            .spaces => |s| for (0..s) |_|
                try uart.writeEvent(.{ .UART = " " }),
        }
    }

    pub fn printLinefeed(_: *Self) !void {
        try uart.writeEvent(.{ .UART = "\n" });
    }

    pub fn pragmaPrinted(_: *Self, _: []const u8) !void {
        unreachable;
    }
};
