const std = @import("std");

const uart = @import("uart.zig");
const proto = @import("proto.zig");
const heap = @import("heap.zig");

const stack = @import("avabasic").stack;
const isa = @import("avabasic").isa;
const PrintLoc = @import("avabasic").PrintLoc;

const VERSION: usize = 1;

// Step 1: create a protocol to communicate over UART.
//
// My main concern is overflowing the SoC UART buffer, but I think I need to
// put that concern aside for now. The TX buffer we can stall the CPU on; the RX
// buffer we'll just put some big sirens on for now. Later we can make a “real”
// protocol with backpressure etc., maybe over USB, but at least it means it's easy
// for us to send lots of data back; we just need to take care when streaming large
// amounts in.
//
// The interface needs to support:
//
// * Upload code for the stack machine.
// * Start, stop, step, inspect, reset the stack machine.
// * Debug print back from the stack machine.
//
// There's a question raised here about who initiates: most of these are
// controller-initiated, but the last one suggests peripheral-initiated. Do we
// just poll for debug messages? I think for now we take this path, it's the
// easiest; later hopefully a Real Interface™ can let us do both.

pub fn main() !void {
    const allocator = heap.allocator;
    // heap.reinitialize_heap();

    var machine: ?stack.Machine(Effects) = null;
    var code: ?[]const u8 = null;

    while (true) {
        try uart.writeResponse(.MACHINE_INIT);

        const req = uart.readRequest(allocator) catch |err| {
            try uart.writer.print("<<err in readRequest: {any}>>", .{err});
            continue;
        };
        defer req.deinit(allocator);
        switch (req) {
            .HELLO => {
                try uart.writeResponse(.{ .HELLO = std.fmt.comptimePrint("AvaCore {d}", .{VERSION}) });
            },
            .MACHINE_INIT => |new_code| {
                try uart.writeResponse(.MACHINE_INIT);

                if (machine) |*m|
                    m.deinit();
                if (code) |c|
                    allocator.free(c);

                effects = .{};
                machine = stack.Machine(Effects).init(allocator, &effects, null);
                code = new_code;

                try machine.?.run(code.?);
            },
        }
    }
}

var effects: Effects = .{};

const Effects = struct {
    const Self = @This();

    pub const Error = error{};

    printloc: PrintLoc = .{},

    pub fn deinit(_: *Self) void {}

    pub fn print(_: *Self, v: isa.Value) !void {
        try isa.printFormat(heap.allocator, uart.writer, v);
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try uart.writer.writeByte('\n'),
            .spaces => |s| try uart.writer.writeByteNTimes(' ', s),
        }
    }

    pub fn printLinefeed(_: *Self) !void {
        try uart.writer.writeByte('\n');
    }

    pub fn pragmaPrinted(_: *Self, _: []const u8) !void {
        unreachable;
    }
};
