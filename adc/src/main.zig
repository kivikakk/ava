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

// https://retrocomputing.stackexchange.com/a/27805/20624
const FLIP_MS = 266;

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

    const scale = 1.3;

    var window = try SDL.createWindow("Ava BASIC ADC", .default, .default, 640 * scale, 400 * scale, .{});
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true, .target_texture = true, .present_vsync = true });
    defer renderer.destroy();

    try renderer.setScale(scale, scale);

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

    const screen = [_]u16{0x0700} ** (80 * 25);
    var mouse_x: u16 = 100;
    var mouse_y: u16 = 100;
    var cursor_on = true;
    const cursor_x = 0;
    const cursor_y = 0;

    var until_flip: i16 = FLIP_MS;
    var last_tick = SDL.getTicks64();

    var running = true;
    while (running) {
        while (SDL.pollEvent()) |ev|
            switch (ev) {
                .mouse_motion => |motion| {
                    // const old_x = mouse_x;
                    // const old_y = mouse_y;

                    mouse_x = @intFromFloat(@as(f32, @floatFromInt(motion.x)) / scale);
                    mouse_y = @intFromFloat(@as(f32, @floatFromInt(motion.y)) / scale);

                    // if (mouse_x != old_x or mouse_y != old_y)
                    //     text_refresh();
                },
                .quit => running = false,
                else => {},
            };

        try renderer.clear();

        for (0..25) |y|
            for (0..80) |x| {
                var pair = screen[y * 80 + x];
                if (mouse_x / 8 == x and mouse_y / 16 == y)
                    pair = ((7 - (pair >> 12)) << 12) |
                        ((7 - ((pair >> 8) & 0xF)) << 8) |
                        (pair & 0xFF);
                try font.render(renderer, pair, x, y);
            };

        if (cursor_on) {
            const pair = screen[cursor_y * 80 + cursor_x];
            const fg = Font.CgaColors[(pair >> 8) & 0xF];
            try renderer.setColorRGBA(@intCast(fg >> 16), @intCast((fg >> 8) & 0xFF), @intCast(fg & 0xFF), 255);
            try renderer.fillRect(.{
                .x = @intCast(cursor_x * 8),
                .y = @intCast(cursor_y * 16 + 16 - 3),
                .width = 8,
                .height = 2,
            });
        }

        renderer.present();

        const this_tick = SDL.getTicks64();
        const delta_tick = this_tick - last_tick;

        last_tick = this_tick;
        until_flip -= @intCast(delta_tick);
        if (until_flip <= 0) {
            until_flip += FLIP_MS;
            cursor_on = !cursor_on;
        }

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
