const std = @import("std");

const Args = @This();

alloc: std.mem.Allocator,
vcd_out: ?[]const u8,

pub fn parse(alloc: std.mem.Allocator) !Args {
    var vcd_out: ?[]const u8 = null;

    var argv = try std.process.argsWithAllocator(alloc);
    defer argv.deinit();

    _ = argv.next();

    var arg_state: enum { root, vcd } = .root;
    while (argv.next()) |arg| {
        switch (arg_state) {
            .root => {
                if (std.mem.eql(u8, arg, "--vcd"))
                    arg_state = .vcd
                else
                    std.debug.panic("unknown argument: \"{s}\"", .{arg});
            },
            .vcd => {
                vcd_out = arg;
                arg_state = .root;
            },
        }
    }
    if (arg_state != .root) std.debug.panic("missing argument for --vcd", .{});

    return .{
        .alloc = alloc,
        .vcd_out = if (vcd_out) |m| try alloc.dupe(u8, m) else null,
    };
}

pub fn deinit(self: *Args) void {
    if (self.vcd_out) |m| self.alloc.free(m);
}
