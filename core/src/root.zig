const std = @import("std");

const main = @import("./main.zig");
const uart = @import("./uart.zig");
const mmio = @import("./mmio.zig");

extern const text_right: anyopaque;
extern const data_left: anyopaque;
extern const data_right: anyopaque;
extern const sp_left: anyopaque;

pub export fn core_start_zig() noreturn {
    var src = @intFromPtr(&text_right);
    var dst = @intFromPtr(&data_left);

    while (dst < @intFromPtr(&data_right)) : ({
        src += 4;
        dst += 4;
    })
        @as(*u32, @ptrFromInt(dst)).* = @as(*const u32, @ptrFromInt(src)).*;
    while (dst < @intFromPtr(&sp_left)) : (dst += 4)
        @as(*u32, @ptrFromInt(dst)).* = 0;

    // Please note: std.debug.panic reserves more than 4096 bytes of stack space in
    // std.debug.panicExtra.
    main.main() catch |err|
        std.debug.panic("err in main: {}", .{err});
    core_exit();
}

inline fn core_exit() noreturn {
    mmio.CSR_EXIT.* = 1;
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

    try uart.writeEvent(.{ .ERROR = msg });

    core_exit();
}
