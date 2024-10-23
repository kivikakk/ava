const std = @import("std");
const Allocator = std.mem.Allocator;
const serial = @import("serial");
const SDL = @import("sdl2");

const proto = @import("avacore").proto;
const Parser = @import("avabasic").Parser;
const Compiler = @import("avabasic").Compiler;
const Args = @import("./Args.zig");
const EventThread = @import("./EventThread.zig");
const Kyuubey = @import("./Kyuubey.zig");
const Font = @import("./Font.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    var handle: std.posix.fd_t = undefined;
    var reader: std.io.AnyReader = undefined;
    var writer: std.io.AnyWriter = undefined;

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

            handle = port.handle;
            reader = port.reader().any();
            writer = port.writer().any();
        },
        .socket => |path| {
            const port = std.net.connectUnixSocket(path) catch |err| switch (err) {
                error.FileNotFound => std.debug.panic("file not found accessing '{s}'", .{path}),
                error.ConnectionRefused => std.debug.panic("connection refused connecting to '{s}' -- cxxrtl not running?", .{path}),
                else => return err,
            };

            handle = port.handle;
            reader = port.reader().any();
            writer = port.writer().any();
        },
    }

    return exe(allocator, args.filename, args.scale, handle, reader, writer);
}

// https://retrocomputing.stackexchange.com/a/27805/20624
const FLIP_MS = 266;

// https://ejmastnak.com/tutorials/arch/typematic-rate/
const TYPEMATIC_DELAY = 500;
const TYPEMATIC_REPEAT = 1000 / 25;

fn exe(
    allocator: Allocator,
    filename: ?[]const u8,
    scale: f32,
    handle: std.posix.fd_t,
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
) !void {
    var et = try EventThread.init(allocator, reader, handle);
    defer et.deinit();

    {
        try proto.Request.write(.HELLO, writer);
        const ev = et.readWait();
        defer ev.deinit(allocator);
        std.debug.assert(ev == .VERSION);
        std.debug.print("connected to {s}\n", .{ev.VERSION});
    }

    {
        try proto.Request.write(.MACHINE_INIT, writer);
        const ev = et.readWait();
        defer ev.deinit(allocator);
        std.debug.assert(ev == .OK);
    }

    var c = try Compiler.init(allocator, null);
    defer c.deinit();

    // ---

    try SDL.init(.{ .video = true, .events = true });
    defer SDL.quit();

    var font = try Font.fromGlyphTxt(allocator, @embedFile("fonts/8x16.txt"));
    defer font.deinit();

    const request_width: usize = @intFromFloat(@as(f32, @floatFromInt(80 * font.char_width)) * scale);
    const request_height: usize = @intFromFloat(@as(f32, @floatFromInt(25 * font.char_height)) * scale);

    var window = try SDL.createWindow(
        "Ava BASIC ADC",
        .default,
        .default,
        request_width,
        request_height,
        .{ .allow_high_dpi = true },
    );
    defer window.destroy();

    var renderer = try SDL.createRenderer(window, null, .{ .accelerated = true, .target_texture = true, .present_vsync = true });
    defer renderer.destroy();

    if ((try renderer.getOutputSize()).width_pixels == request_width * 2)
        try renderer.setScale(scale * 2, scale * 2)
    else
        try renderer.setScale(scale, scale);

    _ = try SDL.showCursor(false);

    try font.prepare(renderer);

    var qb = try Kyuubey.init(allocator, renderer, font, filename);
    defer qb.deinit();

    var until_flip: i16 = FLIP_MS;
    var last_tick = SDL.getTicks64();

    var keydown_tick: u64 = 0;
    var keydown_sym: SDL.Keycode = .unknown;
    var keydown_mod: SDL.KeyModifierSet = undefined;
    var typematic_on = false;

    var old_x: usize = 0;
    var old_y: usize = 0;
    var mouse_down: ?SDL.MouseButton = null;

    var running = true;
    while (running) {
        if (keydown_tick > 0 and !typematic_on and last_tick >= keydown_tick + TYPEMATIC_DELAY) {
            typematic_on = true;
            keydown_tick = last_tick;
            try qb.keyPress(keydown_sym, keydown_mod);
        } else if (keydown_tick > 0 and typematic_on and last_tick >= keydown_tick + TYPEMATIC_REPEAT) {
            keydown_tick = last_tick;
            try qb.keyPress(keydown_sym, keydown_mod);
        }

        while (SDL.pollEvent()) |ev|
            switch (ev) {
                .key_down => |key| {
                    if (key.is_repeat) break;

                    try qb.keyDown(key.keycode, key.modifiers);
                    try qb.keyPress(key.keycode, key.modifiers);
                    keydown_tick = SDL.getTicks64();
                    keydown_sym = key.keycode;
                    keydown_mod = key.modifiers;
                    typematic_on = false;
                },
                .key_up => |key| {
                    try qb.keyUp(key.keycode);
                    keydown_tick = 0;
                },
                .mouse_motion => |motion| {
                    qb.mouse_x = @intFromFloat(@as(f32, @floatFromInt(motion.x)) / scale);
                    qb.mouse_y = @intFromFloat(@as(f32, @floatFromInt(motion.y)) / scale);

                    if (qb.mouse_x != old_x or qb.mouse_y != old_y) {
                        if (mouse_down) |button|
                            try qb.mouseDrag(button, old_x, old_y);
                        try qb.textRefresh();
                    }

                    old_x = qb.mouse_x;
                    old_y = qb.mouse_y;
                },
                .mouse_button_down => |button| {
                    qb.mouse_x = @intFromFloat(@as(f32, @floatFromInt(button.x)) / scale);
                    qb.mouse_y = @intFromFloat(@as(f32, @floatFromInt(button.y)) / scale);

                    if (qb.mouse_x != old_x or qb.mouse_y != old_y)
                        try qb.textRefresh();

                    try qb.mouseDown(button.button, button.clicks);

                    mouse_down = button.button;

                    old_x = qb.mouse_x;
                    old_y = qb.mouse_y;
                },
                .mouse_button_up => |button| {
                    qb.mouse_x = @intFromFloat(@as(f32, @floatFromInt(button.x)) / scale);
                    qb.mouse_y = @intFromFloat(@as(f32, @floatFromInt(button.y)) / scale);

                    if (qb.mouse_x != old_x or qb.mouse_y != old_y)
                        try qb.textRefresh();

                    try qb.mouseUp(button.button, button.clicks);

                    mouse_down = null;

                    old_x = qb.mouse_x;
                    old_y = qb.mouse_y;
                },
                .quit => running = false,
                else => {},
            };

        const this_tick = SDL.getTicks64();
        const delta_tick = this_tick - last_tick;

        last_tick = this_tick;
        until_flip -= @intCast(delta_tick);
        if (until_flip <= 0) {
            until_flip += FLIP_MS;
            qb.cursor_on = !qb.cursor_on;
            try qb.textRefresh();
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
