const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");

const SimController = @import("./SimController.zig");
const UartConnector = @import("./UartConnector.zig");

const SimThread = @This();

sim_controller: *SimController,
alloc: std.mem.Allocator,

cxxrtl: Cxxrtl,
vcd: ?Cxxrtl.Vcd,

clk: Cxxrtl.Object(bool),
rst: Cxxrtl.Object(bool),

uart_connector: UartConnector,

pub fn init(alloc: Allocator, sim_controller: *SimController) SimThread {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (sim_controller.vcd_out != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");

    const uart_connector = UartConnector.init(cxxrtl, alloc);

    return .{
        .sim_controller = sim_controller,
        .alloc = alloc,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .clk = clk,
        .rst = rst,
        .uart_connector = uart_connector,
    };
}

pub fn deinit(self: *SimThread) void {
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

pub fn run(self: *SimThread) !void {
    self.sim_controller.lock();
    self.rst.next(true);
    self.tick();
    self.tick();
    self.rst.next(false);
    self.sim_controller.unlock();

    while (self.sim_controller.lockIfRunning()) {
        defer self.sim_controller.unlock();
        self.tick();

        switch (self.uart_connector.tick()) {
            .nop => {},
            .data => |b| {
                std.debug.print("{c}", .{b});
            },
        }

        self.tick();
    }

    try self.writeVcd();
}

fn tick(self: *SimThread) void {
    self.clk.next(!self.clk.curr());
    self.cxxrtl.step();
    if (self.vcd) |*vcd| vcd.sample();

    self.sim_controller.tick_number += 1;
}

fn writeVcd(self: *SimThread) !void {
    if (self.vcd) |*vcd| {
        const buffer = try vcd.read(self.alloc);
        defer self.alloc.free(buffer);

        var file = try std.fs.cwd().createFile(self.sim_controller.vcd_out.?, .{});
        defer file.close();

        try file.writeAll(buffer);
    }
}
