const std = @import("std");
const Allocator = std.mem.Allocator;

const loc = @import("loc.zig");
const parse = @import("parse.zig");
const print = @import("print.zig");
const compile = @import("compile.zig");
const stack = @import("stack.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (std.os.argv.len == 2) {
        return mainRun(allocator, std.mem.span(std.os.argv[1]));
    } else if (std.os.argv.len == 3) {
        const opt = std.mem.span(std.os.argv[1]);
        if (std.ascii.eqlIgnoreCase(opt, "--ast")) {
            return mainAst(allocator, std.mem.span(std.os.argv[2]));
        } else if (std.ascii.eqlIgnoreCase(opt, "--pp")) {
            return mainPp(allocator, std.mem.span(std.os.argv[2]));
        }
    }

    usage();
}

fn usage() noreturn {
    std.debug.print("Usage: {s} [--ast] FILE.BAS\n", .{std.os.argv[0]});
    std.process.exit(1);
}

fn handleErr(err: anyerror, errorloc: loc.Loc) @TypeOf(err) {
    std.debug.print("loc: ({d}:{d})\n", .{ errorloc.row, errorloc.col });
    return err;
}

fn mainRun(allocator: Allocator, filename: []const u8) !void {
    const inp = try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorloc: loc.Loc = .{};
    const code = compile.compile(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer allocator.free(code);

    var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator, std.io.getStdOut()));
    defer m.deinit();

    try m.run(code);
}

fn mainAst(allocator: Allocator, filename: []const u8) !void {
    const inp = try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorloc: loc.Loc = .{};
    const sx = parse.parse(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer parse.free(allocator, sx);

    const outwr = std.io.getStdOut().writer();
    for (sx) |s| {
        try std.fmt.format(outwr, "{any}\n", .{s});
    }
}

fn mainPp(allocator: Allocator, filename: []const u8) !void {
    const inp = try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorloc: loc.Loc = .{};
    const sx = parse.parse(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer parse.free(allocator, sx);

    const out = try print.print(allocator, sx);
    defer allocator.free(out);

    try std.io.getStdOut().writeAll(out);
}

const RunEffects = struct {
    const Self = @This();

    allocator: Allocator,
    out: std.fs.File,
    outwr: std.fs.File.Writer,

    pub fn init(allocator: Allocator, out: std.fs.File) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .out = out,
            .outwr = out.writer(),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn print(self: *Self, vx: []const stack.Value) !void {
        try stack.printFormat(self.outwr, vx);
        try self.out.sync();
    }
};
