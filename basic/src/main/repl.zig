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

    try common.stdout.tc.setColor(common.stdout.wr, .bright_cyan);
    try common.stdout.wr.writeAll("Ava BASIC\n");
    try common.stdout.tc.setColor(common.stdout.wr, .reset);

    var errorinfo: ErrorInfo = .{};
    var c = try Compiler.init(allocator, &errorinfo);
    defer c.deinit();

    var m = stack.Machine(common.RunEffects).init(allocator, try common.RunEffects.init(allocator), &errorinfo);
    defer m.deinit();

    while (true) {
        defer errorinfo.clear(allocator);

        // TODO: readline(-like).
        try common.stdout.tc.setColor(common.stdout.wr, .reset);
        try common.stdout.wr.writeAll("> ");
        try common.stdout.tc.setColor(common.stdout.wr, .bold);
        try common.stdout.bw.flush();

        const inp = try common.stdin.rd.readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse
            break;
        defer allocator.free(inp);

        try common.stdout.tc.setColor(common.stdout.wr, .reset);

        errorinfo = .{};
        const sx = Parser.parse(allocator, inp, &errorinfo) catch |err| {
            try common.handleError("parse", err, errorinfo, .stdout, .caret);
            continue;
        };
        defer Parser.free(allocator, sx);

        if (options.pp) {
            const out = try print.print(allocator, sx);
            defer allocator.free(out);

            try common.stdout.tc.setColor(common.stdout.wr, .blue);
            try common.stdout.wr.writeAll(out);
            try common.stdout.tc.setColor(common.stdout.wr, .reset);
            try common.stdout.bw.flush();
        }

        if (options.ast) {
            try common.stdout.tc.setColor(common.stdout.wr, .green);
            for (sx) |s|
                try s.formatAst(0, common.stdout.wr);
            try common.stdout.tc.setColor(common.stdout.wr, .reset);
            try common.stdout.wr.writeByte('\n');
            try common.stdout.bw.flush();
        }

        const code = c.compileStmts(sx) catch |err| {
            try common.handleError("compile", err, errorinfo, .stdout, .caret);
            continue;
        };
        defer allocator.free(code);

        if (options.bc) {
            try common.xxd(code);
            try common.disasm(allocator, code);
        }

        m.run(code) catch |err| {
            try common.handleError("run", err, errorinfo, .stdout, .loc);
            continue;
        };
    }

    try common.stdout.tc.setColor(common.stdout.wr, .reset);
    try common.stdout.wr.writeAll("\ngoobai\n");
    try common.stdout.bw.flush();
}
