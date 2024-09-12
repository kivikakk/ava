const std = @import("std");

const main = @import("main.zig");
const uart = @import("uart.zig");

// Please note: std.debug.panic reserves more than 4096 bytes of stack space in
// std.debug.panicExtra.
pub export fn core_start_zig() noreturn {
    main.main() catch |err|
        std.debug.panic("err in main: {}", .{err});
    core_exit();
}

inline fn core_exit() noreturn {
    const CSR_EXIT: *volatile u8 = @ptrFromInt(0xf001_0000);
    CSR_EXIT.* = 1;
    try uart.writer.print("core_exit finished\n", .{});
    while (true) {}
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    _ = error_return_trace;
    _ = ret_addr;

    try uart.writer.print("\n!!! Panic: {s}\n", .{msg});

    core_exit();
}
