const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");

const proto = @import("avacore").proto;

const SimController = @import("./SimController.zig");
const UartProtoConnector = @import("./UartProtoConnector.zig");
const SpiFlashConnector = @import("./SpiFlashConnector.zig");

const SimThread = @This();

sim_controller: *SimController,
allocator: std.mem.Allocator,

cxxrtl: Cxxrtl,
vcd: ?Cxxrtl.Vcd,

clk: Cxxrtl.Object(bool),
rst: Cxxrtl.Object(bool),
running: Cxxrtl.Object(bool),

uart_proto_connector: UartProtoConnector,
spi_flash_connector: SpiFlashConnector,

pub fn init(allocator: Allocator, sim_controller: *SimController) SimThread {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (sim_controller.vcd_out != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");
    const running = cxxrtl.get(bool, "running");

    const uart_proto_connector = UartProtoConnector.init(allocator, cxxrtl);
    const spi_flash_connector = SpiFlashConnector.init(cxxrtl);

    return .{
        .sim_controller = sim_controller,
        .allocator = allocator,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .clk = clk,
        .rst = rst,
        .uart_proto_connector = uart_proto_connector,
        .spi_flash_connector = spi_flash_connector,
        .running = running,
    };
}

pub fn deinit(self: *SimThread) void {
    self.uart_proto_connector.deinit();
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

pub fn run(self: *SimThread) !void {
    var state: union(enum) {
        init,
        wait_hello,
        wait_machine_init,
        end: usize,
    } = .init;

    self.tick();
    while (self.sim_controller.lockIfRunning()) {
        defer self.sim_controller.unlock();
        self.tick();

        self.spi_flash_connector.tick();
        try self.uart_proto_connector.tick();

        switch (state) {
            .init => if (try self.uart_proto_connector.recv(.MACHINE_INIT)) |_| {
                try self.uart_proto_connector.send(.HELLO);
                state = .wait_hello;
            },
            .wait_hello => if (try self.uart_proto_connector.recv(.HELLO)) |id| {
                defer proto.Response.deinit(self.allocator, .HELLO, id);
                std.debug.print("got hello: [{s}]\n", .{id});

                const code = "\x01\x01\x00\x01\x02\x00\x07\x00\x04\x06";
                try self.uart_proto_connector.send(.{ .MACHINE_INIT = code });
                state = .wait_machine_init;
            },
            .wait_machine_init => if (try self.uart_proto_connector.recv(.MACHINE_INIT)) |_| {
                state = .{ .end = 0 };
            },
            .end => |*n| {
                if (self.uart_proto_connector.recv_buffer.popOrNull()) |c| {
                    if (std.ascii.isPrint(c))
                        std.debug.print("{c}", .{c})
                    else
                        std.debug.print("<{x:0>2}>", .{c});
                    n.* += 1;
                    if (n.* == 6) {
                        try self.uart_proto_connector.send(.EXIT);
                    }
                }
            },
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
