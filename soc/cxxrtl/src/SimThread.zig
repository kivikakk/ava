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

uart_proto_connector: UartProtoConnector,
running: Cxxrtl.Object(bool),

pub fn init(allocator: Allocator, sim_controller: *SimController) SimThread {
    const cxxrtl = Cxxrtl.init();

    var vcd: ?Cxxrtl.Vcd = null;
    if (sim_controller.vcd_out != null) vcd = Cxxrtl.Vcd.init(cxxrtl);

    const clk = cxxrtl.get(bool, "clk");
    const rst = cxxrtl.get(bool, "rst");

    const uart_connector = UartConnector.init(cxxrtl, allocator);
    const uart_proto_connector = UartProtoConnector.init(allocator, uart_connector);
    const running = cxxrtl.get(bool, "running");

    return .{
        .sim_controller = sim_controller,
        .allocator = allocator,
        .cxxrtl = cxxrtl,
        .vcd = vcd,
        .clk = clk,
        .rst = rst,
        .uart_proto_connector = uart_proto_connector,
        .running = running,
    };
}

pub fn deinit(self: *SimThread) void {
    self.uart_proto_connector.deinit();
    if (self.vcd) |*vcd| vcd.deinit();
    self.cxxrtl.deinit();
}

const UartProtoConnector = struct {
    const Self = @This();

    allocator: Allocator,
    uart_connector: UartConnector,
    recv_buffer: std.ArrayList(u8),

    fn init(allocator: Allocator, uart_connector: UartConnector) Self {
        return .{
            .allocator = allocator,
            .uart_connector = uart_connector,
            .recv_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    fn deinit(self: Self) void {
        self.uart_connector.deinit();
        self.recv_buffer.deinit();
    }

    fn tick(self: *Self) !void {
        const b = switch (self.uart_connector.tick()) {
            .nop => return,
            .data => |b| b,
        };

        std.debug.print("{{{x:0>2}}}", .{b});
        try self.recv_buffer.append(b);
    }

    fn send(self: *Self, req: proto.Request) !void {
        try req.write(self.uart_connector.tx_buffer.writer());
    }

    fn recv(self: *Self, comptime kind: proto.RequestKind) !?std.meta.TagPayload(proto.Response, kind) {
        var fbs = std.io.fixedBufferStream(self.recv_buffer.items);
        if (proto.Response.read(self.allocator, fbs.reader(), kind)) |resp| {
            self.recv_buffer.replaceRange(0, fbs.pos, &.{}) catch unreachable;
            return resp;
        } else |err| switch (err) {
            error.EndOfStream => return null,
            else => return err,
        }
    }
};

// Need to connect UartConnector to a generic reader/writer interface so this
// can use the same thing as the actual tool that'll connect to the live FPGA.

pub fn run(self: *SimThread) !void {
    var state: enum { init, wait_hello, wait_tervist, end } = .init;

    self.tick();
    while (self.sim_controller.lockIfRunning()) {
        defer self.sim_controller.unlock();
        self.tick();

        try self.uart_proto_connector.tick();

        switch (state) {
            .init => {
                try self.uart_proto_connector.send(.HELLO);
                state = .wait_hello;
            },
            .wait_hello => if (try self.uart_proto_connector.recv(.HELLO)) |id| {
                defer proto.Response.deinit(self.allocator, .HELLO, id);
                std.debug.print("got hello: [{s}]\n", .{id});
                try self.uart_proto_connector.send(.TERVIST);
                state = .wait_tervist;
            },
            .wait_tervist => if (try self.uart_proto_connector.recv(.TERVIST)) |n| {
                defer proto.Response.deinit(self.allocator, .TERVIST, n);
                std.debug.print("got tervist: 0x{x:0>16}\n", .{n});
                state = .end;
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
