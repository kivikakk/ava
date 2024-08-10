const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiler = @import("../Compiler.zig");
const stack = @import("../stack.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    common.usageFor(status, "run", "[options] [file]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Executes [file].
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
    const mode: common.RunMode =
        if (options.bas)
        .bas
    else if (options.avc)
        .avc
    else if (common.runModeFromFilename(filename)) |m| m else {
        std.debug.print("run: could not infer run mode from filename; specify --bas or --avc.\n", .{});
        usage(1);
    };

    const inp = if (std.mem.eql(u8, filename, "-"))
        try common.stdin.file.readToEndAlloc(allocator, 1048576)
    else
        try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorinfo: ErrorInfo = .{};
    const code = switch (mode) {
        .bas => Compiler.compileText(allocator, inp, &errorinfo) catch |err| {
            try common.handleError("compile", err, errorinfo, .stderr, .loc);
            try common.handlesDeinit();
            std.process.exit(2);
        },
        .avc => inp,
    };
    defer switch (mode) {
        .bas => allocator.free(code),
        .avc => {},
    };

    var m = stack.Machine(common.RunEffects).init(allocator, try common.RunEffects.init(allocator), &errorinfo);
    defer m.deinit();

    m.run(code) catch |err| {
        try common.handleError("run", err, errorinfo, .stderr, .loc);
        try common.handlesDeinit();
        std.process.exit(3);
    };
}
