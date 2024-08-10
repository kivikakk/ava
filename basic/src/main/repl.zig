const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("../Parser.zig");
const print = @import("../print.zig");
const Compiler = @import("../Compiler.zig");
const stack = @import("../stack.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    common.usageFor(status, "repl", "[options]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Starts an interactive BASIC session.
        \\
        \\Per-line options:
        \\
        \\  --pp           Pretty-print source before executing
        \\  --ast          Print source AST before executing
        \\  --bc           Pretty-print bytecode before executing
        \\
    );
}

pub fn main(allocator: Allocator, options: opts.Repl) !void {
    if (opts.global.options.help)
        usage(0);

    if (opts.global.positionals.len != 0) {
        std.debug.print("repl: no positional arguments expected.\n", .{});
        usage(1);
    }

    try common.stdoutTc.setColor(common.stdoutWr, .bright_cyan);
    try common.stdoutWr.writeAll("Ava BASIC\n");
    try common.stdoutTc.setColor(common.stdoutWr, .reset);

    var errorinfo: ErrorInfo = .{};
    var c = try Compiler.init(allocator, &errorinfo);
    defer c.deinit();

    var m = stack.Machine(common.RunEffects).init(allocator, try common.RunEffects.init(allocator), &errorinfo);
    defer m.deinit();

    while (true) {
        defer errorinfo.clear(allocator);

        // TODO: readline(-like).
        try common.stdoutTc.setColor(common.stdoutWr, .reset);
        try common.stdoutWr.writeAll("> ");
        try common.stdoutTc.setColor(common.stdoutWr, .bold);
        try common.stdoutBw.flush();

        const inp = try common.stdinRd.readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse
            break;
        defer allocator.free(inp);

        try common.stdoutTc.setColor(common.stdoutWr, .reset);

        errorinfo = .{};
        const sx = Parser.parse(allocator, inp, &errorinfo) catch |err| {
            try common.handleError("parse", err, errorinfo, .stdout, .caret);
            continue;
        };
        defer Parser.free(allocator, sx);

        if (options.pp) {
            const out = try print.print(allocator, sx);
            defer allocator.free(out);

            try common.stdoutTc.setColor(common.stdoutWr, .blue);
            try common.stdoutWr.writeAll(out);
            try common.stdoutTc.setColor(common.stdoutWr, .reset);
            try common.stdoutBw.flush();
        }

        if (options.ast) {
            try common.stdoutTc.setColor(common.stdoutWr, .green);
            for (sx) |s|
                try s.formatAst(0, common.stdoutWr);
            try common.stdoutTc.setColor(common.stdoutWr, .reset);
            try common.stdoutWr.writeByte('\n');
            try common.stdoutBw.flush();
        }

        const code = c.compileStmts(sx) catch |err| {
            try common.handleError("compile", err, errorinfo, .stdout, .caret);
            continue;
        };
        defer allocator.free(code);

        if (options.bc)
            try common.xxd(code);

        m.run(code) catch |err| {
            try common.handleError("run", err, errorinfo, .stdout, .loc);
            continue;
        };
    }

    try common.stdoutTc.setColor(common.stdoutWr, .reset);
    try common.stdoutWr.writeAll("\ngoobai\n");
    try common.stdoutBw.flush();
}
