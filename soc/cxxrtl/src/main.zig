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

    var sim_controller = try SimController.start(allocator, args.vcd_out);
    defer sim_controller.joinDeinit();

    while (sim_controller.lockIfRunning()) {
        defer sim_controller.unlock();
        // if (sim_controller.tickNumber() > 1_000) {
        //     sim_controller.halt();
        // }
    }

    std.debug.print("\nfinished at tick number {d}\n", .{sim_controller.tickNumber()});
}
