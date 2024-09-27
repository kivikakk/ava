const std = @import("std");
const testing = std.testing;

pub const Parser = @import("./Parser.zig");
pub const isa = @import("./isa.zig");
pub const Compiler = @import("./Compiler.zig");
pub const stack = @import("./stack.zig");
pub const PrintLoc = @import("./PrintLoc.zig");

comptime {
    testing.refAllDeclsRecursive(@import("./Token.zig"));
    testing.refAllDeclsRecursive(@import("./Tokenizer.zig"));
    testing.refAllDeclsRecursive(@import("./ast/Stmt.zig"));
    testing.refAllDeclsRecursive(@import("./ast/Expr.zig"));
    testing.refAllDeclsRecursive(Parser);
    testing.refAllDeclsRecursive(@import("./print.zig"));
    testing.refAllDeclsRecursive(isa);
    testing.refAllDeclsRecursive(Compiler);
    testing.refAllDeclsRecursive(stack);
    testing.refAllDeclsRecursive(PrintLoc);
    testing.refAllDeclsRecursive(@import("./test.zig"));
    testing.refAllDeclsRecursive(@import("./ty.zig"));
    testing.refAllDeclsRecursive(@import("./LocHandler.zig"));
    testing.refAllDeclsRecursive(@import("./loc.zig"));
    testing.refAllDeclsRecursive(@import("./ErrorInfo.zig"));
}
