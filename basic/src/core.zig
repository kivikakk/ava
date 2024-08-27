const std = @import("std");

const UART: *volatile u8 = @ptrFromInt(0x8000_0000);

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

pub export fn core_start_zig() void {
    UART.* = '%';

    var buf: [8]u8 = undefined;
    buf[0] = readUart();
    buf[1] = readUart();
    buf[2] = readUart();
    buf[3] = readUart();
    buf[4] = readUart();
    buf[5] = readUart();
    buf[6] = readUart();
    buf[7] = readUart();

    var f: [2]f32 = undefined;
    @memcpy(std.mem.sliceAsBytes(f[0..]), &buf);

    f[0] = f[0] / f[1];

    @memcpy(buf[0..4], std.mem.sliceAsBytes(f[0..1]));

    writeUart(buf[0..4]);
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
