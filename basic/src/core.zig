const std = @import("std");

const UART: *volatile u8 = @ptrFromInt(0x8000_0000);

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

var sbuf: [4]u8 = [_]u8{ 't', 'e', 'a', 'n' };
var buf: [4]u8 = undefined;

pub export fn core_start_zig() void {
    UART.* = '%';

    writeUart("henlo ");
    writeUart(&sbuf);

    sbuf[0] = readUart();
    sbuf[1] = readUart();
    sbuf[2] = readUart();
    sbuf[3] = readUart();
    buf[0] = readUart();
    buf[1] = readUart();
    buf[2] = readUart();
    buf[3] = readUart();

    writeUart(&sbuf);
    writeUart(&buf);
}

fn writeUart(m: []const u8) void {
    for (m) |c|
        UART.* = c;
}

fn readUart() u8 {
    while (true) {
        const c = UART.*;
        if (c != 0) return c;
    }
}
