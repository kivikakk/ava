const std = @import("std");

const Args = @import("./Args.zig");
const SimState = @import("./SimState.zig");

var aborted: std.atomic.Value(bool) = .{ .raw = false };
var socket_server_stream: ?std.net.Stream = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try Args.parse(allocator);
    defer args.deinit();

    const uart_socket_path = args.uart orelse "cxxrtl-uart";

    const socket_addr = try std.net.Address.initUnix(uart_socket_path);
    var socket_server = try socket_addr.listen(.{});
    defer socket_server.deinit();

    socket_server_stream = socket_server.stream;

    var sim_state = SimState.init(allocator, &aborted, args.vcd);
    defer sim_state.deinit();

    try std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = sigint },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    while (!aborted.load(.acquire)) {
        std.debug.print("waiting for UART connection on '{s}' ... ", .{uart_socket_path});
        const socket_conn = socket_server.accept() catch |err| {
            if (aborted.load(.acquire)) break;
            return err;
        };
        std.debug.print("accepted!\n", .{});

        defer socket_conn.stream.close();

        const flags = try std.posix.fcntl(socket_conn.stream.handle, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(socket_conn.stream.handle, std.posix.F.SETFL, flags | (1 << @bitOffsetOf(std.posix.O, "NONBLOCK")));

        try sim_state.run(socket_conn.stream);
    }

    std.debug.print("\nfinished at tick number {d}\n", .{sim_state.tick_number});
    try sim_state.writeVcd();
}

fn sigint(_: i32) callconv(.C) void {
    aborted.store(true, .release);
    if (socket_server_stream) |s| s.close();
}
