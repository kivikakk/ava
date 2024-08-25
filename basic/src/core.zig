const std = @import("std");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg;
    _ = error_return_trace;
    _ = ret_addr;
    while (true) {}
}

pub export fn core_start() noreturn {
    writeUart("henlo");
    while (true) {}
}

fn writeUart(comptime m: []const u8) void {
    inline for (m) |c|
        @as(*volatile u8, @ptrFromInt(0x8000_0000)).* = c;
}
