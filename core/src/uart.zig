const std = @import("std");
const uart = @This();

const UART: *volatile u8 = @ptrFromInt(0x8000_0000);
const UART_STATUS: *volatile u16 = @ptrFromInt(0x8000_0000);

pub const writer = std.io.GenericWriter(void, error{}, writeFn){ .context = {} };

fn writeFn(context: void, bytes: []const u8) error{}!usize {
    _ = context;
    for (bytes) |b|
        UART.* = b;
    return bytes.len;
}

pub const reader = std.io.GenericReader(void, error{}, readFn){ .context = {} };

fn readFn(context: void, buffer: []u8) error{}!usize {
    // 0 means EOS, which we never want to signal, so always return a minimum of 1 byte.
    _ = context;
    var i: usize = 0;

    while (i < buffer.len) {
        const cs: u16 = UART_STATUS.*;
        if (cs & 0x100 == 0x100) {
            buffer[i] = @truncate(cs);
            i += 1;
        } else if (i > 0) {
            break;
        }
    }

    return i;
}
