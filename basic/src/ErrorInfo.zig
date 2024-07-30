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
