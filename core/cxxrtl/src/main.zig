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

    var frame_count: usize = 0;

    var img_data: SimThread.ImgData = undefined;

    while (sim_controller.lockIfRunning()) {
        var updated_img_data = false;

        {
            defer sim_controller.unlock();

            updated_img_data = sim_controller.maybeUpdateImgData(&img_data);
        }

        if (updated_img_data) {}

        frame_count += 1;
    }
}
