const std = @import("std");
const testing = std.testing;

comptime {
    testing.refAllDeclsRecursive(@import("token.zig"));
    testing.refAllDeclsRecursive(@import("ast.zig"));
    testing.refAllDeclsRecursive(@import("parse.zig"));
    testing.refAllDeclsRecursive(@import("print.zig"));
    testing.refAllDeclsRecursive(@import("isa.zig"));
    testing.refAllDeclsRecursive(@import("compile.zig"));
    testing.refAllDeclsRecursive(@import("stack.zig"));
}
