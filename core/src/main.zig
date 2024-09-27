const std = @import("std");
const Allocator = std.mem.Allocator;

const eheap = @import("eheap");
const stack = @import("avabasic").stack;
const isa = @import("avabasic").isa;
const PrintLoc = @import("avabasic").PrintLoc;

const uart = @import("./uart.zig");
const proto = @import("./proto.zig");

const VERSION: usize = 3;
const heap = eheap.Heap(64 * 1024);

pub fn main() !void {
    heap.initialize();
    const allocator = heap.allocator;

    var machine: ?stack.Machine(Effects) = null;

    while (true) {
        const req = uart.readRequest(allocator) catch {
            try uart.writeEvent(.{ .ERROR = "readRequest" });
            continue;
        };
        defer req.deinit(allocator);

        switch (req) {
            .HELLO => try uart.writeEvent(.{ .VERSION = std.fmt.comptimePrint("AvaCore {d}", .{VERSION}) }),
            .MACHINE_INIT => {
                if (machine) |*m|
                    m.deinit();

                effects = .{};
                machine = stack.Machine(Effects).init(allocator, &effects, null);
                try uart.writeEvent(.OK);
            },
            .MACHINE_EXEC => |code| {
                if (machine) |*m| {
                    try uart.writeEvent(.OK);
                    try m.run(code);
                } else try uart.writeEvent(.INVALID);
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

    printloc: PrintLoc = .{},

    pub fn deinit(_: *Self) void {}

    pub fn print(_: *Self, v: isa.Value) !void {
        var b = std.ArrayListUnmanaged(u8){};
        defer b.deinit(heap.allocator);
        try isa.printFormat(heap.allocator, b.writer(heap.allocator), v);
        try uart.writeEvent(.{ .DEBUG = b.items });
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try uart.writeEvent(.{ .DEBUG = "\n" }),
            .spaces => |s| for (0..s) |_|
                try uart.writeEvent(.{ .DEBUG = " " }),
        }
    }

    pub fn printLinefeed(_: *Self) !void {
        try uart.writeEvent(.{ .DEBUG = "\n" });
    }

    pub fn pragmaPrinted(_: *Self, _: []const u8) !void {
        unreachable;
    }
};
