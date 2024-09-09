const std = @import("std");
const serial = @import("serial");

const Args = @import("./Args.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    std.debug.print("opening port ...\n", .{});
    const port_path = "/dev/cu.usbserial-ibU1IGlC1";
    var port = std.fs.cwd().openFile(port_path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.panic("file not found accessing '{s}'", .{port_path});
        },
        else => return err,
    };
    defer port.close();

    std.debug.print("configuring port\n", .{});
    try serial.configureSerialPort(port, .{
        .baud_rate = 1_500_000,
    });

    std.debug.print("writing 01\n", .{});
    try port.writer().writeAll("\x01");

    std.debug.print("reading\n", .{});
    while (true) {
        const c = try port.reader().readByte();
        if (std.ascii.isPrint(c))
            std.debug.print("{c}", .{c})
        else
            std.debug.print("<{x:0>2}>", .{c});
    }

    return 0;
}
