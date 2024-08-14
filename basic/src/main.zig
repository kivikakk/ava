const std = @import("std");
const Allocator = std.mem.Allocator;
const args = @import("args");

const opts = @import("main/opts.zig");
const common = @import("main/common.zig");
const commands = .{
    .repl = @import("main/repl.zig"),
    .run = @import("main/run.zig"),
    .compile = @import("main/compile.zig"),
    .pp = @import("main/pp.zig"),
    .ast = @import("main/ast.zig"),
    .bc = @import("main/bc.zig"),
};

fn usage(status: u8) noreturn {
    common.usageFor(status, "[command]", "[options]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Commands:
        \\
        \\  repl           Start an interactive session
        \\  run            Execute a source or object file
        \\  compile        Create object file from source file
        \\
        \\  pp             Pretty-print source
        \\  ast            Print source AST
        \\  bc             Disassemble and pretty-print bytecode
        \\
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    common.handlesInit();
    defer common.handlesDeinit() catch {};

    opts.global = try args.parseWithVerbForCurrentProcess(opts.Global, opts.Command, allocator, .print);
    defer opts.global.deinit();

    const verb = opts.global.verb orelse usage(if (opts.global.options.help) 0 else 1);
    inline for (@typeInfo(std.meta.Tag(opts.Command)).Enum.fields) |f| {
        if (@intFromEnum(verb) == f.value) {
            return @field(commands, f.name).main(allocator, @field(verb, f.name));
        }
    }
}
