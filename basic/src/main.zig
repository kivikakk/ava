const std = @import("std");
const Allocator = std.mem.Allocator;

const compile = @import("compile.zig");
const stack = @import("stack.zig");

pub fn main() !void {
    if (std.os.argv.len != 2) usage();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inp = try std.fs.cwd().readFileAlloc(allocator, "hello.bas", 1048576);
    const code = try compile.compile(allocator, inp);

    var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator));
    defer m.deinit();

    try m.run(code);
}

fn usage() noreturn {
    std.debug.print("Usage: {s} FILE.BAS\n", .{std.os.argv[0]});
    std.process.exit(1);
}

const RunEffects = struct {
    const Self = @This();

    allocator: Allocator,

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn print(_: *Self, vx: []const stack.Value) !void {
        var stdout = std.io.getStdOut();
        try stack.printFormat(stdout.writer(), vx);
        try stdout.sync();
    }
};
