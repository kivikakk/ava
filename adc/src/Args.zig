const std = @import("std");

const Args = @This();

allocator: std.mem.Allocator,

pub fn parse(allocator: std.mem.Allocator) !Args {
    var argv = try std.process.argsWithAllocator(allocator);
    defer argv.deinit();

    _ = argv.next();

    const arg_state: enum { root } = .root;
    while (argv.next()) |arg| {
        switch (arg_state) {
            .root => {
                std.debug.panic("unknown argument: \"{s}\"", .{arg});
            },
        }
    }
    if (arg_state != .root) std.debug.panic("?", .{});

    return .{
        .allocator = allocator,
    };
}

pub fn deinit(_: *Args) void {}
