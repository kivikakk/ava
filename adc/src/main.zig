const std = @import("std");
const serial = @import("serial");

const proto = @import("avacore").proto;
const Args = @import("./Args.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    const port_path = "/dev/cu.usbserial-ibU1IGlC1";
    var port = std.fs.cwd().openFile(port_path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.panic("file not found accessing '{s}'", .{port_path});
        },
        else => return err,
    };
    defer port.close();

    try serial.configureSerialPort(port, .{
        .baud_rate = 1_500_000,
    });

    try proto.Request.write(.HELLO, port.writer());

    const ev = try proto.Event.read(allocator, port.reader());
    defer ev.deinit(allocator);

    std.debug.assert(ev == .VERSION);
    std.debug.print("connected to {s}\n", .{ev.VERSION});
}
