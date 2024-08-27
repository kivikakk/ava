const std = @import("std");

const uart = @import("uart.zig");

const UART: *volatile u8 = @ptrFromInt(0x8000_0000);
const UART_STATUS: *volatile u16 = @ptrFromInt(0x8000_0000);
const CSR_EXIT: *volatile u8 = @ptrFromInt(0x8000_ffff);

pub fn main() void {
    try uart.writer.print("%", .{});

    var buf: [8]u8 = undefined;
    _ = try uart.reader.readAll(&buf);

    var f: [2]f32 = undefined;
    @memcpy(std.mem.sliceAsBytes(f[0..]), &buf);

    f[0] = @floatFromInt(@as(u32, @intFromFloat(f[0])) / @as(u32, @intFromFloat(f[1])));
    @memcpy(buf[0..4], std.mem.sliceAsBytes(f[0..1]));
    try uart.writer.print("{s}", .{buf[0..4]});

    @panic("test panic");
}
