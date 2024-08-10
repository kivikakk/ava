const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiler = @import("../Compiler.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    common.usageFor(status, "compile", "[file]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Compiles BASIC source to Ava BASIC bytecode.
        \\
        \\If the extension of [file] is `.bas', the output file will be the
        \\corresponding `.avc' file. Otherwise, `.avc' will be appended.
        \\
        \\`-' may be given to read from standard input and write to standard
        \\output.
        \\
    );
}

pub fn main(allocator: Allocator, options: opts.Compile) !void {
    _ = options;

    if (opts.global.options.help)
        usage(0);

    if (opts.global.positionals.len != 1) {
        std.debug.print("compile: exactly one [file] expected.\n", .{});
        usage(1);
    }

    const filename = opts.global.positionals[0];

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
    const code = Compiler.compileText(allocator, inp, &errorinfo) catch |err| {
        try stderrtc.setColor(stderrwr, .bright_red);
        try common.showErrorInfo(errorinfo, stderrwr, .loc);
        try std.fmt.format(stderrwr, "compile: {s}\n\n", .{@errorName(err)});
        try stderrtc.setColor(stderrwr, .reset);
        try stderrbw.flush();
        return err;
    };
    defer allocator.free(code);

    if (std.mem.eql(u8, filename, "-")) {
        const stdout = std.io.getStdOut();
        var stdoutbw = std.io.bufferedWriter(stdout.writer());
        const stdoutwr = stdoutbw.writer();

        try stdoutwr.writeAll(code);
        try stdoutbw.flush();
    } else {
        const filenameOut = if (std.ascii.endsWithIgnoreCase(filename, ".bas")) bas: {
            var buf = try allocator.dupe(u8, filename);
            @memcpy(buf[buf.len - 3 ..], "avc");
            break :bas buf;
        } else other: {
            var buf = try allocator.alloc(u8, filename.len + 4);
            @memcpy(buf[0..filename.len], filename);
            @memcpy(buf[buf.len - 4 ..], ".avc");
            break :other buf;
        };
        defer allocator.free(filenameOut);

        try std.fs.cwd().writeFile(.{ .sub_path = filenameOut, .data = code });
    }
}
