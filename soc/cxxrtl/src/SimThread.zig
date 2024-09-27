const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");
const proto = @import("avacore").proto;

const SimController = @import("./SimController.zig");
const UartConnector = @import("./UartConnector.zig");
const SpiFlashConnector = @import("./SpiFlashConnector.zig");

const SimThread = @This();

allocator: std.mem.Allocator,
sim_controller: *SimController,
cxxrtl: Cxxrtl,
vcd: ?Cxxrtl.Vcd,

clk: Cxxrtl.Object(bool),
rst: Cxxrtl.Object(bool),
running: Cxxrtl.Object(bool),

spi_flash_connector: SpiFlashConnector,
uart_connector: UartConnector,

pub fn init(allocator: Allocator, sim_controller: *SimController) SimThread {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (sim_controller.vcd != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");
    const running = cxxrtl.get(bool, "running");

    const spi_flash_connector = SpiFlashConnector.init(cxxrtl);

    return .{
        .allocator = allocator,
        .sim_controller = sim_controller,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .clk = clk,
        .rst = rst,
        .running = running,
        .spi_flash_connector = spi_flash_connector,
        .uart_connector = UartConnector.init(allocator, cxxrtl),
    };
}

pub fn deinit(self: *SimThread) void {
    self.uart_connector.deinit();
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

pub fn run(self: *SimThread) !void {
    // self.tick(); // XXX
    while (self.sim_controller.lockIfRunning()) {
        defer self.sim_controller.unlock();
        self.tick();

        self.spi_flash_connector.tick();

        switch (self.uart_connector.tick()) {
            .nop => {},
            .data => |b| {
                const bv = [1]u8{b};
                try self.sim_controller.uart_stream.writeAll(&bv);
            },
        }

        var bv = [1]u8{undefined};
        if (self.sim_controller.uart_stream.read(&bv)) |n| {
            if (n == 0) {
                std.debug.print("UART disconnected\n", .{});
                self.sim_controller.halt();
            } else {
                try self.uart_connector.tx_buffer.append(bv[0]);
            }
        } else |err| switch (err) {
            error.WouldBlock => {},
            else => return err,
        }

        if (!self.running.curr()) {
            self.sim_controller.halt();
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
        const buffer = try vcd.read(self.allocator);
        defer self.allocator.free(buffer);

        var file = try std.fs.cwd().createFile(self.sim_controller.vcd.?, .{});
        defer file.close();

        try file.writeAll(buffer);
    }
}
