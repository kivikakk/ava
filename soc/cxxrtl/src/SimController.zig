const std = @import("std");

const SimThread = @import("./SimThread.zig");

const SimController = @This();

controller_allocator: std.mem.Allocator,
thread: std.Thread,
vcd: ?[]const u8,
uart_stream: std.net.Stream,
state: SimThread,
mutex: std.Thread.Mutex = .{},
running: bool = true,
tick_number: usize = 0,

pub fn start(allocator: std.mem.Allocator, vcd: ?[]const u8, uart_stream: std.net.Stream) !*SimController {
    var sim_controller = try allocator.create(SimController);
    sim_controller.* = .{
        .controller_allocator = allocator,
        .thread = undefined,
        .vcd = vcd,
        .uart_stream = uart_stream,
        .state = undefined,
    };
    const thread = try std.Thread.spawn(.{}, simThreadStart, .{sim_controller});
    sim_controller.thread = thread;
    return sim_controller;
}

fn simThreadStart(sim_controller: *SimController) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    sim_controller.state = SimThread.init(allocator, sim_controller);
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

pub fn halt(self: *SimController) void {
    self.running = false;
}

pub fn joinDeinit(self: *SimController) void {
    self.thread.join();
    self.controller_allocator.destroy(self);
}
