const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("../Parser.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    std.debug.print(
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Usage: {?s} ast [file]
        \\
        \\Parses [file] and pretty-prints the source. `-' may be given to read from
        \\standard input.
        \\
    ++ common.helpText, .{opts.global.executable_name});
    std.process.exit(status);
}

pub fn main(allocator: Allocator, options: opts.Ast) !void {
    _ = options;

    if (opts.global.options.help)
        usage(0);

    if (opts.global.positionals.len != 1) {
        std.debug.print("ast: exactly one [file] expected.\n", .{});
        usage(1);
    }

    const filename = opts.global.positionals[0];

    const stdout = std.io.getStdOut();
    var stdoutbw = std.io.bufferedWriter(stdout.writer());
    const stdoutwr = stdoutbw.writer();

    const stderr = std.io.getStdErr();
    var stderrbw = std.io.bufferedWriter(stderr.writer());
    const stderrwr = stderrbw.writer();
    var stderrtc = std.io.tty.detectConfig(stderr);

    const inp = if (std.mem.eql(u8, filename, "-"))
        try std.io.getStdIn().readToEndAlloc(allocator, 1048576)
    else
        try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorinfo: ErrorInfo = .{};
    const sx = Parser.parse(allocator, inp, &errorinfo) catch |err| {
        try stderrtc.setColor(stderrwr, .bright_red);
        try common.showErrorInfo(errorinfo, stderrwr, .loc);
        try std.fmt.format(stderrwr, "parse: {s}\n\n", .{@errorName(err)});
        try stderrtc.setColor(stderrwr, .reset);
        try stderrbw.flush();
        return err;
    };
    defer Parser.free(allocator, sx);

    for (sx) |s|
        try s.formatAst(0, stdoutwr);
    try stdoutwr.writeByte('\n');
    try stdoutbw.flush();
}
