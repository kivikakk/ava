const std = @import("std");

const SimThread = @import("./SimThread.zig");

const SimController = @This();

controller_alloc: std.mem.Allocator,
thread: std.Thread,
vcd_out: ?[]const u8,
state: SimThread,
mutex: std.Thread.Mutex = .{},
running: bool = true,
tick_number: usize = 0,

pub fn start(alloc: std.mem.Allocator, vcd_out: ?[]const u8) !*SimController {
    var sim_controller = try alloc.create(SimController);
    sim_controller.* = .{
        .controller_alloc = alloc,
        .thread = undefined,
        .vcd_out = vcd_out,
        .state = undefined,
    };
    const thread = try std.Thread.spawn(.{}, simThreadStart, .{sim_controller});
    sim_controller.thread = thread;
    return sim_controller;
}

fn simThreadStart(sim_controller: *SimController) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    sim_controller.state = SimThread.init(alloc, sim_controller);
    defer sim_controller.state.deinit();

    sim_controller.state.run() catch std.debug.panic("SimThread.run threw", .{});
}

pub fn lockIfRunning(self: *SimController) bool {
    self.lock();
    if (!self.running) {
        self.unlock();
        return false;
    }
    return true;
}

pub fn lock(self: *SimController) void {
    self.mutex.lock();
}

pub fn unlock(self: *SimController) void {
    self.mutex.unlock();
}

pub fn tickNumber(self: *const SimController) usize {
    return self.tick_number;
}

pub fn maybeUpdateImgData(self: *SimController, img_data: *SimThread.ImgData) bool {
    if (!self.state.img_data_new)
        return false;

    img_data.* = self.state.img_data;
    self.state.img_data_new = false;
    return true;
}

pub fn halt(self: *SimController) void {
    self.running = false;
}

pub fn joinDeinit(self: *SimController) void {
    self.thread.join();
    self.controller_alloc.destroy(self);
}
