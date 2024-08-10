const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiler = @import("../Compiler.zig");
const stack = @import("../stack.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    std.debug.print(
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Usage: {?s} run [options] [file]
        \\
        \\The extension of [file] will be used to guess the run mode if no relevant
        \\option is given. `-' may be given to read from standard input.
        \\
        \\Run mode options:
        \\
        \\  --bas          Interpret [file] as BASIC source
        \\  --avc          Interpret [file] as Ava BASIC object file
        \\
    ++ common.helpText, .{opts.global.executable_name});
    std.process.exit(status);
}

pub fn main(allocator: Allocator, options: opts.Run) !void {
    if (opts.global.options.help)
        usage(0);

    if (opts.global.positionals.len != 1) {
        std.debug.print("run: exactly one [file] expected.\n", .{});
        usage(1);
    }

    if (options.bas and options.avc) {
        std.debug.print("run: cannot specify both --bas and --avc.\n", .{});
        usage(1);
    }

    const filename = opts.global.positionals[0];
    const mode: enum { bas, avc } =
        if (options.bas) .bas else if (options.avc) .avc else if (std.ascii.endsWithIgnoreCase(filename, ".bas")) .bas else if (std.ascii.endsWithIgnoreCase(filename, ".avc")) .avc else {
        std.debug.print("run: could not infer run mode from filename; specify --bas or --avc.\n", .{});
        usage(1);
    };

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
    const code: []const u8 = switch (mode) {
        .bas => Compiler.compileText(allocator, inp, &errorinfo) catch |err| {
            try stderrtc.setColor(stderrwr, .bright_red);
            try common.showErrorInfo(errorinfo, stderrwr, .loc);
            try std.fmt.format(stderrwr, "compile: {s}\n\n", .{@errorName(err)});
            try stderrtc.setColor(stderrwr, .reset);
            try stderrbw.flush();
            return err;
        },
        .avc => inp,
    };
    defer switch (mode) {
        .bas => allocator.free(code),
        .avc => {},
    };

    var m = stack.Machine(common.RunEffects).init(allocator, try common.RunEffects.init(allocator, std.io.getStdOut()), &errorinfo);
    defer m.deinit();

    m.run(code) catch |err| {
        try stderrtc.setColor(stderrwr, .bright_red);
        try common.showErrorInfo(errorinfo, stderrwr, .loc);
        try std.fmt.format(stderrwr, "run error: {s}\n\n", .{@errorName(err)});
        try stderrtc.setColor(stderrwr, .reset);
        try stderrbw.flush();
        return err;
    };
}
