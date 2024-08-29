const std = @import("std");

const uart = @import("uart.zig");
const proto = @import("proto.zig");
const stack = @import("avabasic").stack;

const VERSION: usize = 0;

var heap: [0x900]u8 = undefined;

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
    var fba = std.heap.FixedBufferAllocator.init(&heap);
    const allocator = fba.allocator();

    // var machine = stack.Machine(Effects).init(, , )

    while (true) : (fba.reset()) {
        const req = try uart.readRequest(allocator);
        defer req.deinit(allocator);
        switch (req) {
            .HELLO => {
                // Include an alloc to force BSS to exist for now.
                const m = try std.fmt.allocPrint(allocator, "AvaCore {d}", .{VERSION});
                defer allocator.free(m);
                try uart.writeResponse(.{ .HELLO = m });
            },
            .TERVIST => {
                try uart.writeResponse(.{ .TERVIST = 0xabcd1234_ef077123 });
            },
        }
    }
}
