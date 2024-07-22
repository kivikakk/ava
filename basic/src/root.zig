const std = @import("std");
const testing = std.testing;

comptime {
    testing.refAllDeclsRecursive(@import("token.zig"));
    testing.refAllDeclsRecursive(@import("parse.zig"));
}
