const std = @import("std");
const Allocator = std.mem.Allocator;
const Cxxrtl = @import("zxxrtl");

const proto = @import("avacore").proto;

const UartConnector = @import("./UartConnector.zig");

const UartProtoConnector = @This();

// Need to connect UartConnector to a generic reader/writer interface so this
// can use the same thing as the actual tool that'll connect to the live FPGA.

allocator: Allocator,
uart_connector: UartConnector,
recv_buffer: std.ArrayList(u8),

pub fn init(allocator: Allocator, cxxrtl: Cxxrtl) UartProtoConnector {
    return .{
        .allocator = allocator,
        .uart_connector = UartConnector.init(allocator, cxxrtl),
        .recv_buffer = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: UartProtoConnector) void {
    self.uart_connector.deinit();
    self.recv_buffer.deinit();
}

pub fn tick(self: *UartProtoConnector) !void {
    const b = switch (self.uart_connector.tick()) {
        .nop => return,
        .data => |b| b,
    };

    try self.recv_buffer.append(b);
}

pub fn send(self: *UartProtoConnector, req: proto.Request) !void {
    try req.write(self.uart_connector.tx_buffer.writer());
}

pub fn recv(self: *UartProtoConnector) !?proto.Event {
    var fbs = std.io.fixedBufferStream(self.recv_buffer.items);
    if (proto.Event.read(self.allocator, fbs.reader())) |ev| {
        self.recv_buffer.replaceRange(0, fbs.pos, &.{}) catch unreachable;
        return ev;
    } else |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    }
}
