const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiler = @import("../Compiler.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    common.usageFor(status, "bc", "[file]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Pretty-prints Ava BASIC bytecode.
        \\
        \\The extension of [file] will be used to guess the run mode if no relevant
        \\option is given. `-' may be given to read from standard input.
        \\
        \\Run mode options:
        \\
        \\  --bas          Treat [file] as BASIC source
        \\  --avc          Treat [file] as Ava BASIC object file
        \\
    );
}

pub fn main(allocator: Allocator, options: opts.Bc) !void {
    if (opts.global.options.help)
        usage(0);

    if (opts.global.positionals.len != 1) {
        std.debug.print("bc: exactly one [file] expected.\n", .{});
        usage(1);
    }

    const filename = opts.global.positionals[0];
    const mode: common.RunMode =
        if (options.bas)
        .bas
    else if (options.avc)
        .avc
    else if (common.runModeFromFilename(filename)) |m| m else {
        std.debug.print("bc: could not infer run mode from filename; specify --bas or --avc.\n", .{});
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
    const code = switch (mode) {
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

    try common.xxd(code);
}
