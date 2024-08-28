const std = @import("std");

const uart = @import("uart.zig");
const proto = @import("proto.zig");

// Step 1: create a protocol to communicate over UART.
//
// My main concern is overflowing the SoC UART buffer, but I think I need to
// put that concern aside for now. The TX buffer we can stall the CPU on; the RX
// buffer we'll just put some big sirens on for now. Later we can make a “real”
// protocol with backpressure etc., maybe over USB.
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

pub fn main() void {
    while (true) {
        const req = proto.Request.read(uart.reader);
        switch (req) {
            .HELLO => {
                try (proto.Response{ .HELLO = "AvaCore 000" }).write(uart.writer);
            },
        }
    }
}
