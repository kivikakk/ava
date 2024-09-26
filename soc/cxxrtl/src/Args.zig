const std = @import("std");

const Args = @This();

allocator: std.mem.Allocator,
vcd: ?[]const u8,
uart: ?[]const u8,

pub fn parse(allocator: std.mem.Allocator) !Args {
    var vcd: ?[]const u8 = null;
    var uart: ?[]const u8 = null;

    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    _ = argv.next();

    var arg_state: enum { root, vcd, uart } = .root;
    while (argv.next()) |arg| {
        switch (arg_state) {
            .root => {
                if (std.mem.eql(u8, arg, "--vcd"))
                    arg_state = .vcd
                else if (std.mem.eql(u8, arg, "--uart"))
                    arg_state = .uart
                else
                    std.debug.panic("unknown argument: \"{s}\"", .{arg});
            },
            .vcd => {
                vcd = arg;
                arg_state = .root;
            },
            .uart => {
                uart = arg;
                arg_state = .root;
            },
        }
    }
    switch (arg_state) {
        .root => {},
        .vcd => std.debug.panic("missing argument for --vcd", .{}),
        .uart => std.debug.panic("missing argument for --uart", .{}),
    }

    return .{
        .allocator = allocator,
        .vcd = if (vcd) |m| try allocator.dupe(u8, m) else null,
        .uart = if (uart) |m| try allocator.dupe(u8, m) else null,
    };
}

pub fn deinit(self: *Args) void {
    if (self.uart) |m| self.allocator.free(m);
    if (self.vcd) |m| self.allocator.free(m);
}
