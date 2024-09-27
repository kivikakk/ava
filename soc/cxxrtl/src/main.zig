const std = @import("std");

const Args = @import("./Args.zig");
const SimController = @import("./SimController.zig");
const SimThread = @import("./SimThread.zig");

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

    while (true) {
        std.debug.print("waiting for UART connection on '{s}' ... ", .{uart_socket_path});
        const socket_conn = try socket_server.accept();
        std.debug.print("accepted!\n", .{});

        defer socket_conn.stream.close();

        const flags = try std.posix.fcntl(socket_conn.stream.handle, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(socket_conn.stream.handle, std.posix.F.SETFL, flags | (1 << @bitOffsetOf(std.posix.O, "NONBLOCK")));

        var sim_controller = try SimController.start(allocator, args.vcd, socket_conn.stream);
        defer sim_controller.joinDeinit();

        while (sim_controller.lockIfRunning()) {
            defer sim_controller.unlock();
        }

        std.debug.print("\nfinished at tick number {d}\n", .{sim_controller.tickNumber()});
    }
}
