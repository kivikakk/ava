const std = @import("std");

const Args = @This();

const Port = union(enum) {
    serial: []const u8,
    socket: []const u8,
};

allocator: std.mem.Allocator,
port: Port,

pub fn parse(allocator: std.mem.Allocator) !Args {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    const argv0 = argv.next().?;

    var port: ?Port = null;

    var state: enum { root, serial, socket } = .root;
    while (argv.next()) |arg| {
        switch (state) {
            .root => {
                if (std.mem.eql(u8, arg, "--serial"))
                    state = .serial
                else if (std.mem.eql(u8, arg, "--socket"))
                    state = .socket
                else {
                    std.debug.print("unknown argument: \"{s}\"\n", .{arg});
                    usage(argv0);
                }
            },
            .serial => {
                port = .{ .serial = try allocator.dupe(u8, arg) };
                state = .root;
            },
            .socket => {
                port = .{ .socket = try allocator.dupe(u8, arg) };
                state = .root;
            },
        }
    }

    if (state != .root or port == null)
        usage(argv0);

    return .{
        .allocator = allocator,
        .port = port.?,
    };
}

pub fn deinit(self: Args) void {
    switch (self.port) {
        .serial, .socket => |s| self.allocator.free(s),
    }
}

fn usage(argv0: []const u8) noreturn {
    std.debug.print("usage: {s} {{--serial PORT | --socket SOCKET}}\n", .{argv0});
    std.process.exit(1);
}
