const std = @import("std");

pub const proto = @import("proto.zig");

comptime {
    std.testing.refAllDeclsRecursive(proto);
}
