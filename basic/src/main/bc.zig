const std = @import("std");
const Allocator = std.mem.Allocator;

const Compiler = @import("../Compiler.zig");
const ErrorInfo = @import("../ErrorInfo.zig");
const isa = @import("../isa.zig");

const opts = @import("opts.zig");
const common = @import("common.zig");

fn usage(status: u8) noreturn {
    common.usageFor(status, "bc", "[options] [file]",
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Disassembles and pretty-prints Ava BASIC bytecode.
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

    try common.xxd(code);
    try disasm(allocator, code);
}

fn disasm(allocator: Allocator, code: []const u8) !void {
    _ = allocator;

    var i: usize = 0;
    while (i < code.len) {
        try std.fmt.format(common.stdout.wr, "{x:0>4}: ", .{i});

        const op = @as(isa.Opcode, @enumFromInt(code[i]));
        i += 1;

        try common.stdout.tc.setColor(common.stdout.wr, .bright_green);
        try common.stdout.wr.writeAll(@tagName(op));
        try common.stdout.tc.setColor(common.stdout.wr, .reset);

        switch (op) {
            .PUSH_IMM_INTEGER => {
                const n = std.mem.readInt(i16, code[i..][0..2], .little);
                i += 2;
                try std.fmt.format(common.stdout.wr, " {} (0x{x})", .{ n, n });
            },
            .PUSH_IMM_LONG => {
                const n = std.mem.readInt(i32, code[i..][0..4], .little);
                i += 4;
                try std.fmt.format(common.stdout.wr, " {} (0x{x})", .{ n, n });
            },
            .PUSH_IMM_SINGLE => {
                var r: [1]f32 = undefined;
                @memcpy(std.mem.sliceAsBytes(r[0..]), code[i..][0..4]);
                i += 4;
                try std.fmt.format(common.stdout.wr, " {}", .{r[0]});
            },
            .PUSH_IMM_DOUBLE => {
                var r: [1]f64 = undefined;
                @memcpy(std.mem.sliceAsBytes(r[0..]), code[i..][0..8]);
                i += 8;
                try std.fmt.format(common.stdout.wr, " {}", .{r[0]});
            },
            .PUSH_IMM_STRING => {
                const len = std.mem.readInt(u16, code[i..][0..2], .little);
                i += 2;
                const str = code[i..][0..len];
                i += len;
                try std.fmt.format(common.stdout.wr, " \"{s}\" (len {d})", .{ str, len });
            },
            .PUSH_VARIABLE => {
                const slot = code[i];
                i += 1;
                try std.fmt.format(common.stdout.wr, " slot {d}", .{slot});
            },
            .PROMOTE_INTEGER_LONG,
            .COERCE_INTEGER_SINGLE,
            .COERCE_INTEGER_DOUBLE,
            .COERCE_LONG_INTEGER,
            .COERCE_LONG_SINGLE,
            .COERCE_LONG_DOUBLE,
            .COERCE_SINGLE_INTEGER,
            .COERCE_SINGLE_LONG,
            .PROMOTE_SINGLE_DOUBLE,
            .COERCE_DOUBLE_INTEGER,
            .COERCE_DOUBLE_LONG,
            .COERCE_DOUBLE_SINGLE,
            => {},
            .LET => {
                const slot = code[i];
                i += 1;
                try std.fmt.format(common.stdout.wr, " slot {d}", .{slot});
            },
            .BUILTIN_PRINT,
            .BUILTIN_PRINT_COMMA,
            .BUILTIN_PRINT_LINEFEED,
            => {},
            .OPERATOR_ADD_INTEGER,
            .OPERATOR_ADD_LONG,
            .OPERATOR_ADD_SINGLE,
            .OPERATOR_ADD_DOUBLE,
            .OPERATOR_ADD_STRING,
            .OPERATOR_MULTIPLY_INTEGER,
            .OPERATOR_MULTIPLY_LONG,
            .OPERATOR_MULTIPLY_SINGLE,
            .OPERATOR_MULTIPLY_DOUBLE,
            .OPERATOR_FDIVIDE_INTEGER,
            .OPERATOR_FDIVIDE_LONG,
            .OPERATOR_FDIVIDE_SINGLE,
            .OPERATOR_FDIVIDE_DOUBLE,
            .OPERATOR_IDIVIDE_INTEGER,
            .OPERATOR_IDIVIDE_LONG,
            .OPERATOR_IDIVIDE_SINGLE,
            .OPERATOR_IDIVIDE_DOUBLE,
            .OPERATOR_SUBTRACT_INTEGER,
            .OPERATOR_SUBTRACT_LONG,
            .OPERATOR_SUBTRACT_SINGLE,
            .OPERATOR_SUBTRACT_DOUBLE,
            .OPERATOR_NEGATE_INTEGER,
            .OPERATOR_NEGATE_LONG,
            .OPERATOR_NEGATE_SINGLE,
            .OPERATOR_NEGATE_DOUBLE,
            .OPERATOR_EQ_INTEGER,
            .OPERATOR_EQ_LONG,
            .OPERATOR_EQ_SINGLE,
            .OPERATOR_EQ_DOUBLE,
            .OPERATOR_EQ_STRING,
            .OPERATOR_NEQ_INTEGER,
            .OPERATOR_NEQ_LONG,
            .OPERATOR_NEQ_SINGLE,
            .OPERATOR_NEQ_DOUBLE,
            .OPERATOR_NEQ_STRING,
            .OPERATOR_LT_INTEGER,
            .OPERATOR_LT_LONG,
            .OPERATOR_LT_SINGLE,
            .OPERATOR_LT_DOUBLE,
            .OPERATOR_LT_STRING,
            .OPERATOR_GT_INTEGER,
            .OPERATOR_GT_LONG,
            .OPERATOR_GT_SINGLE,
            .OPERATOR_GT_DOUBLE,
            .OPERATOR_GT_STRING,
            .OPERATOR_LTE_INTEGER,
            .OPERATOR_LTE_LONG,
            .OPERATOR_LTE_SINGLE,
            .OPERATOR_LTE_DOUBLE,
            .OPERATOR_LTE_STRING,
            .OPERATOR_GTE_INTEGER,
            .OPERATOR_GTE_LONG,
            .OPERATOR_GTE_SINGLE,
            .OPERATOR_GTE_DOUBLE,
            .OPERATOR_GTE_STRING,
            .OPERATOR_AND_INTEGER,
            .OPERATOR_AND_LONG,
            .OPERATOR_AND_SINGLE,
            .OPERATOR_AND_DOUBLE,
            .OPERATOR_OR_INTEGER,
            .OPERATOR_OR_LONG,
            .OPERATOR_OR_SINGLE,
            .OPERATOR_OR_DOUBLE,
            .OPERATOR_XOR_INTEGER,
            .OPERATOR_XOR_LONG,
            .OPERATOR_XOR_SINGLE,
            .OPERATOR_XOR_DOUBLE,
            => {},
            .PRAGMA_PRINTED => unreachable,
        }

        try common.stdout.wr.writeByte('\n');
        try common.stdout.bw.flush();
    }
}
