const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");
const proto = @import("avacore").proto;

const UartConnector = @import("./UartConnector.zig");
const SpiFlashConnector = @import("./SpiFlashConnector.zig");

const SimState = @This();

allocator: std.mem.Allocator,
aborted: *std.atomic.Value(bool),
cxxrtl: Cxxrtl,
vcd: ?Cxxrtl.Vcd,
vcd_path: ?[]const u8,
tick_number: usize = 0,

clk: Cxxrtl.Object(bool),
rst: Cxxrtl.Object(bool),
running: Cxxrtl.Object(bool),

spi_flash_connector: SpiFlashConnector,
uart_connector: UartConnector,

pub fn init(allocator: Allocator, aborted: *std.atomic.Value(bool), vcd_path: ?[]const u8) SimState {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (vcd_path != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");
    const running = cxxrtl.get(bool, "running");

    const spi_flash_connector = SpiFlashConnector.init(cxxrtl);

    return .{
        .allocator = allocator,
        .aborted = aborted,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .vcd_path = vcd_path,
        .clk = clk,
        .rst = rst,
        .running = running,
        .spi_flash_connector = spi_flash_connector,
        .uart_connector = UartConnector.init(allocator, cxxrtl),
    };
}

pub fn deinit(self: *SimState) void {
    self.uart_connector.deinit();
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

pub fn run(self: *SimState, uart_stream: std.net.Stream) !void {
    while (!self.aborted.load(.acquire)) {
        self.tick();

        self.spi_flash_connector.tick();

        switch (self.uart_connector.tick()) {
            .nop => {},
            .data => |b| {
                std.debug.print("rtl->ADC: {x:0>2}\n", .{b});
                try uart_stream.writer().writeByte(b);
            },
        }

        self.tick();

        if (uart_stream.reader().readByte()) |b| {
            std.debug.print("ADC->rtl: {x:0>2}\n", .{b});
            try self.uart_connector.tx_buffer.append(b);
        } else |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("UART disconnected\n", .{});
                break;
            },
            error.WouldBlock => {},
            else => return err,
        }

        if (!self.running.curr())
            self.aborted.store(true, .release);
    }
}

fn tick(self: *SimState) void {
    self.clk.next(!self.clk.curr());
    self.cxxrtl.step();
    if (self.vcd) |*vcd| vcd.sample();

    self.tick_number += 1;
}

pub fn writeVcd(self: *SimState) !void {
    if (self.vcd) |*vcd| {
        const buffer = try vcd.read(self.allocator);
        defer self.allocator.free(buffer);

        var file = try std.fs.cwd().createFile(self.vcd_path.?, .{});
        defer file.close();

        try file.writeAll(buffer);
    }
}
