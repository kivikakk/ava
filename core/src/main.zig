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
    defer if (machine) |*m| m.deinit();

    while (true) {
        const req = uart.readRequest(allocator) catch {
            try uart.writeEvent(.{ .ERROR = "readRequest" });
            continue;
        };
        defer req.deinit(allocator);

        switch (req) {
            .HELLO => try uart.writeEvent(.{ .VERSION = std.fmt.comptimePrint("AvaCore {d}", .{VERSION}) }),
            .MACHINE_QUERY => try uart.writeEvent(if (machine != null) .OK else .INVALID),
            .MACHINE_INIT => {
                if (machine) |*m|
                    m.deinit();

                effects = .{};
                machine = stack.Machine(Effects).init(allocator, &effects, null);
                try uart.writeEvent(.OK);
            },
            .MACHINE_EXEC => |code| {
                if (machine) |*m| {
                    try m.run(code);
                    try uart.writeEvent(.OK);
                } else try uart.writeEvent(.INVALID);
            },
            .DUMP_HEAP => {
                var allocs: usize = 0;
                var holes: usize = 0;
                var ptr = heap.start();
                while (true) : (ptr = ptr.next() orelse break) {
                    if (ptr.occupied)
                        allocs += 1
                    else
                        holes += 1;
                }

                const s = try std.fmt.allocPrint(
                    allocator,
                    "in use: {d}/{d}\n{d} alloc(s), {d} hole(s)\n",
                    .{ heap.ArenaSize - heap.arena_free, heap.ArenaSize, allocs, holes },
                );
                defer allocator.free(s);

                try uart.writeEvent(.{ .DEBUG = s });
                try uart.writeEvent(.OK);
            },
            .EXIT => break,
        }
    }

    try uart.writeEvent(.{ .DEBUG = "exiting main" });
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
