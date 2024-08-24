const std = @import("std");

const Args = @import("./Args.zig");
const SimController = @import("./SimController.zig");
const SimThread = @import("./SimThread.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try Args.parse(alloc);
    defer args.deinit();

    var sim_controller = try SimController.start(alloc, args.vcd_out);
    defer sim_controller.joinDeinit();

    while (sim_controller.lockIfRunning()) {
        {
            defer sim_controller.unlock();
        }
    }
}
