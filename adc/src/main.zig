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

    switch (args.port) {
        .serial => |path| {
            const port = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.panic("file not found accessing '{s}'", .{path});
                },
                else => return err,
            };
            defer port.close();

            try serial.configureSerialPort(port, .{
                .baud_rate = 1_500_000,
            });

            try exe(allocator, port.reader(), port.writer());
        },
        .socket => |path| {
            const port = std.net.connectUnixSocket(path) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.panic("file not found accessing '{s}'", .{path});
                },
                else => return err,
            };
            defer port.close();

            try exe(allocator, port.reader(), port.writer());
        },
    }
}

fn exe(allocator: std.mem.Allocator, reader: anytype, writer: anytype) !void {
    try proto.Request.write(.HELLO, writer);

    var ev = try proto.Event.read(allocator, reader);
    defer ev.deinit(allocator);

    if (ev == .READY) {
        ev = try proto.Event.read(allocator, reader);
    }

    std.debug.assert(ev == .VERSION);
    std.debug.print("connected to {s}\n", .{ev.VERSION});
}
