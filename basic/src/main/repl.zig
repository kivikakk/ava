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

    const stdout = std.io.getStdOut();
    var stdoutbw = std.io.bufferedWriter(stdout.writer());
    const stdoutwr = stdoutbw.writer();
    var ttyconf = std.io.tty.detectConfig(stdout);

    const stdin = std.io.getStdIn();
    var stdinbuf = std.io.bufferedReader(stdin.reader());
    var stdinrd = stdinbuf.reader();

    try ttyconf.setColor(stdoutwr, .bright_cyan);
    try stdoutwr.writeAll("Ava BASIC\n");
    try ttyconf.setColor(stdoutwr, .reset);

    var errorinfo: ErrorInfo = .{};
    var c = try Compiler.init(allocator, &errorinfo);
    defer c.deinit();

    var m = stack.Machine(common.RunEffects).init(allocator, try common.RunEffects.init(allocator, stdout), &errorinfo);
    defer m.deinit();

    while (true) {
        defer errorinfo.clear(allocator);

        // TODO: readline(-like).
        try ttyconf.setColor(stdoutwr, .reset);
        try stdoutwr.writeAll("> ");
        try ttyconf.setColor(stdoutwr, .bold);
        try stdoutbw.flush();

        const inp = try stdinrd.readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse
            break;
        defer allocator.free(inp);

        try ttyconf.setColor(stdoutwr, .reset);

        errorinfo = .{};
        const sx = Parser.parse(allocator, inp, &errorinfo) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try common.showErrorInfo(errorinfo, stdoutwr, .caret);
            try std.fmt.format(stdoutwr, "parse: {s}\n\n", .{@errorName(err)});
            try ttyconf.setColor(stdoutwr, .reset);
            continue;
        };
        defer Parser.free(allocator, sx);

        if (options.pp) {
            const out = try print.print(allocator, sx);
            defer allocator.free(out);

            try ttyconf.setColor(stdoutwr, .blue);
            try stdoutwr.writeAll(out);
            try ttyconf.setColor(stdoutwr, .reset);
            try stdoutbw.flush();
        }

        if (options.ast) {
            try ttyconf.setColor(stdoutwr, .green);
            for (sx) |s|
                try s.formatAst(0, stdoutwr);
            try ttyconf.setColor(stdoutwr, .reset);
            try stdoutwr.writeByte('\n');
            try stdoutbw.flush();
        }

        const code = c.compileStmts(sx) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try common.showErrorInfo(errorinfo, stdoutwr, .caret);
            try std.fmt.format(stdoutwr, "compile: {s}\n\n", .{@errorName(err)});
            try ttyconf.setColor(stdoutwr, .reset);
            continue;
        };
        defer allocator.free(code);

        if (options.bc)
            try common.xxd(code);

        m.run(code) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try common.showErrorInfo(errorinfo, stdoutwr, .loc);
            try std.fmt.format(stdoutwr, "run error: {s}\n\n", .{@errorName(err)});
            try ttyconf.setColor(stdoutwr, .reset);
            continue;
        };
    }

    try ttyconf.setColor(stdoutwr, .reset);
    try stdoutwr.writeAll("\ngoobai\n");
    try stdoutbw.flush();
}
