const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");

const proto = @import("avacore").proto;

const SimController = @import("./SimController.zig");
const UartConnector = @import("./UartConnector.zig");

const SimThread = @This();

sim_controller: *SimController,
allocator: std.mem.Allocator,

cxxrtl: Cxxrtl,
vcd: ?Cxxrtl.Vcd,

clk: Cxxrtl.Object(bool),
rst: Cxxrtl.Object(bool),

uart_connector: UartConnector,
running: Cxxrtl.Object(bool),

pub fn init(allocator: Allocator, sim_controller: *SimController) SimThread {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (sim_controller.vcd_out != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");

    const uart_connector = UartConnector.init(cxxrtl, allocator);
    const running = cxxrtl.get(bool, "running");

    return .{
        .sim_controller = sim_controller,
        .allocator = allocator,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .clk = clk,
        .rst = rst,
        .uart_connector = uart_connector,
        .running = running,
    };
}

pub fn deinit(self: *SimThread) void {
    self.uart_connector.deinit();
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

pub fn run(self: *SimThread) !void {
    var state: enum { init, recv_hello_sz, recv_hello_b, end } = .init;
    var hello_sz: usize = undefined;
    var hello_b: std.ArrayListUnmanaged(u8) = undefined;

    self.tick();
    while (self.sim_controller.lockIfRunning()) {
        defer self.sim_controller.unlock();
        self.tick();

        const uart_tick = self.uart_connector.tick();

        switch (state) {
            .init => {
                std.debug.assert(uart_tick == .nop);
                try (proto.Request{ .HELLO = {} }).write(self.uart_connector.tx_buffer.writer());
                state = .recv_hello_sz;
            },
            .recv_hello_sz => switch (uart_tick) {
                .nop => {},
                .data => |b| {
                    std.debug.assert(b != 0);
                    hello_sz = b;
                    hello_b = try std.ArrayListUnmanaged(u8).initCapacity(self.allocator, hello_sz);
                    state = .recv_hello_b;
                },
            },
            .recv_hello_b => switch (uart_tick) {
                .nop => {},
                .data => |b| {
                    hello_b.appendAssumeCapacity(b);
                    if (hello_b.items.len == hello_sz) {
                        std.debug.print("got hello: [{s}]\n", .{hello_b.items});
                        state = .end;
                    }
                },
            },
            .end => {},
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

        var file = try std.fs.cwd().createFile(self.sim_controller.vcd_out.?, .{});
        defer file.close();

        try file.writeAll(buffer);
    }
}
