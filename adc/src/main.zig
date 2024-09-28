const std = @import("std");
const Allocator = std.mem.Allocator;
const serial = @import("serial");
const SDL = @import("sdl2");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
const Args = @import("./Args.zig");
const EventThread = @import("./EventThread.zig");
const Font = @import("./Font.zig");

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

            try serial.configureSerialPort(port, .{
                .baud_rate = 1_500_000,
            });

            return exe(allocator, port.reader().any(), port.handle, port.writer().any());
        },
        .socket => |path| {
            const port = std.net.connectUnixSocket(path) catch |err| switch (err) {
                error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
                error.ConnectionRefused => std.debug.panic("connection refused connecting to '{s}' -- cxxrtl not running?", .{path}),
                else => return err,
            };

            return exe(allocator, port.reader().any(), port.handle, port.writer().any());
        },
    }
}

fn exe(allocator: Allocator, reader: std.io.AnyReader, reader_handle: std.posix.fd_t, writer: std.io.AnyWriter) !void {
    var et = try EventThread.init(allocator, reader, reader_handle);
    defer et.deinit();

    {
        try proto.Request.write(.HELLO, writer);
        const ev = et.readWait();
        defer ev.deinit(allocator);
        std.debug.assert(ev == .VERSION);
        std.debug.print("connected to {s}\n", .{ev.VERSION});
    }

    try SDL.init(.{ .video = true, .events = true });
    defer SDL.quit();

    var window = try SDL.createWindow("Ava BASIC ADC", .default, .default, 640, 480, .{});
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true, .target_texture = true });
    defer renderer.destroy();

    var font = try Font.fromData(renderer, @embedFile("cp437.vga"));
    defer font.deinit();

    _ = try SDL.showCursor(false);

    {
        try proto.Request.write(.MACHINE_INIT, writer);
        const ev = et.readWait();
        defer ev.deinit(allocator);
        std.debug.assert(ev == .OK);
    }

    var c = try Compiler.init(allocator, null);
    defer c.deinit();

    var running = true;
    while (running) {
        while (SDL.pollEvent()) |ev|
            switch (ev) {
                .quit => running = false,
                else => {},
            };

        try renderer.clear();
        renderer.present();

        // std.debug.print("> ", .{});
        // const inp = try std.io.getStdIn().reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse return;
        // defer allocator.free(inp);

        // if (std.ascii.eqlIgnoreCase(inp, "~heap")) {
        //     try proto.Request.write(.DUMP_HEAP, writer);
        //     const ev = et.readWait();
        //     defer ev.deinit(allocator);
        //     std.debug.assert(ev == .OK);
        //     continue;
        // }

        // const sx = try Parser.parse(allocator, inp, null);
        // defer Parser.free(allocator, sx);

        // if (sx.len > 0) {
        //     const code = try c.compileStmts(sx);
        //     defer allocator.free(code);

        //     try proto.Request.write(.{ .MACHINE_EXEC = code }, writer);
        //     const ev = et.readWait();
        //     defer ev.deinit(allocator);
        //     std.debug.assert(ev == .OK);
        // }
    }
}
