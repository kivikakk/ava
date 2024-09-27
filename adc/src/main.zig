const std = @import("std");
const serial = @import("serial");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
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
                error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
                error.Unexpected => std.debug.panic("unexpected error opening '{s}' -- not a serial port?", .{path}),
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
                error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
                error.ConnectionRefused => std.debug.panic("connection refused connecting to '{s}' -- cxxrtl not running?", .{path}),
                else => return err,
            };
            defer port.close();

            try exe(allocator, port.reader(), port.writer());
        },
    }
}

fn exe(allocator: std.mem.Allocator, reader: anytype, writer: anytype) !void {
    {
        try proto.Request.write(.HELLO, writer);
        const ev = try proto.Event.read(allocator, reader);
        defer ev.deinit(allocator);
        std.debug.assert(ev == .VERSION);
        std.debug.print("connected to {s}\n", .{ev.VERSION});
    }

    {
        try proto.Request.write(.MACHINE_INIT, writer);
        const ev = try proto.Event.read(allocator, reader);
        defer ev.deinit(allocator);
        std.debug.assert(ev == .OK);
    }

    var c = try Compiler.init(allocator, null);
    defer c.deinit();

    while (true) {
        std.debug.print("> ", .{});
        const inp = try std.io.getStdIn().reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse return;
        defer allocator.free(inp);

        const sx = try Parser.parse(allocator, inp, null);
        defer Parser.free(allocator, sx);

        const code = try c.compileStmts(sx);
        defer allocator.free(code);

        try proto.Request.write(.{ .MACHINE_EXEC = code }, writer);
        const ev = try proto.Event.read(allocator, reader);
        defer ev.deinit(allocator);
        std.debug.assert(ev == .OK);
    }
}
