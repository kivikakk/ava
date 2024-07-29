const std = @import("std");
const testing = std.testing;

comptime {
    testing.refAllDeclsRecursive(@import("Token.zig"));
    testing.refAllDeclsRecursive(@import("Tokenizer.zig"));
    testing.refAllDeclsRecursive(@import("ast.zig"));
    testing.refAllDeclsRecursive(@import("Parser.zig"));
    testing.refAllDeclsRecursive(@import("print.zig"));
    testing.refAllDeclsRecursive(@import("isa.zig"));
    testing.refAllDeclsRecursive(@import("compile.zig"));
    testing.refAllDeclsRecursive(@import("stack.zig"));
}
