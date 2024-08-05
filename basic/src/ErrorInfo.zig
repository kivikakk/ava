const std = @import("std");
const Allocator = std.mem.Allocator;

const loc = @import("loc.zig");
const Loc = loc.Loc;

const ErrorInfo = @This();

loc: ?Loc = null,
msg: ?[]const u8 = null,

pub fn clear(self: *ErrorInfo, allocator: Allocator) void {
    if (self.msg) |m|
        allocator.free(m);
    self.msg = null;
}

pub fn ret(target: anytype, err: anytype, comptime fmt: []const u8, args: anytype) (Allocator.Error || @TypeOf(err)) {
    comptime {
        if (!@hasField(@TypeOf(target.*), "allocator"))
            @compileError("ErrorInfo.ret target must have allocator field");
        if (!@hasField(@TypeOf(target.*), "errorinfo"))
            @compileError("ErrorInfo.ret target must have errorinfo field");
    }

    if (target.errorinfo) |ei|
        ei.msg = try std.fmt.allocPrint(target.allocator, fmt, args);
    return err;
}

pub fn format(self: ErrorInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    var space = false;
    if (self.loc) |l| {
        try l.format(fmt, options, writer);
        space = true;
    }
    if (self.msg) |m| {
        if (space) try writer.writeByte(' ');
        try std.fmt.format(writer, "\"{s}\"", .{m});
        space = true;
    }
}
