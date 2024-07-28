const std = @import("std");
const Allocator = std.mem.Allocator;
const args = @import("args");

const loc = @import("loc.zig");
const parse = @import("parse.zig");
const print = @import("print.zig");
const isa = @import("isa.zig");
const compile = @import("compile.zig");
const stack = @import("stack.zig");

const Options = struct {
    pp: bool = false,
    ast: bool = false,
    bc: bool = false,
    help: bool = false,
};
var options: Options = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed = try args.parseForCurrentProcess(Options, allocator, .print);
    defer parsed.deinit();

    options = parsed.options;

    if (options.help) usage(parsed.executable_name, 0);
    if (parsed.positionals.len > 1) usage(parsed.executable_name, 1);

    if (parsed.positionals.len == 1) {
        return mainRun(allocator, parsed.positionals[0]);
    } else {
        return mainInteractive(allocator);
    }
}

fn usage(executable_name: ?[:0]const u8, status: u8) noreturn {
    std.debug.print(
        \\Usage: {?s} [options] [file]
        \\Executes [file] when given, otherwise starts an interactive session.
        \\
        \\Options:
        \\
        \\  --pp       Pretty-prints [file] without executing.
        \\  --ast      Prints the AST of [file] without executing.
        \\  --bc       Dumps the bytecode compiled from [file] without executing.
        \\  --help     Shows this information.
        \\
        \\Multiple of --pp, --ast, and/or --bc can be given at once.
        \\
        \\If --pp, --ast, and/or --bc are given without [file], the corresponding
        \\action is taken on each input line, and the line is executed.
        \\
        \\Ava BASIC  Copyright (C) 2024  Asherah Erin Connor
        \\This program comes with ABSOLUTELY NO WARRANTY; for details type `LICENCE
        \\WARRANTY'. This is free software, and you are welcome to redistribute it
        \\under certain conditions; type `LICENCE CONDITIONS' for details.
    , .{executable_name});
    std.process.exit(status);
}

fn mainRun(allocator: Allocator, filename: []const u8) !void {
    const inp = try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorloc: loc.Loc = .{};
    const sx = parse.parse(allocator, inp, &errorloc) catch |err| {
        if (errorloc.row != 0)
            std.fmt.format(std.io.getStdErr().writer(), "parse error loc: ({d}:{d})\n", .{ errorloc.row, errorloc.col }) catch unreachable;
        return err;
    };
    defer parse.free(allocator, sx);

    if (options.pp) {
        const out = try print.print(allocator, sx);
        defer allocator.free(out);

        try std.io.getStdOut().writeAll(out);
    }

    if (options.ast) {
        const outwr = std.io.getStdOut().writer();
        for (sx) |s|
            try s.formatAst(0, outwr);
    }

    if (options.bc) {
        const code = try compile.compileStmts(allocator, sx);
        defer allocator.free(code);

        try xxd(code);
    }

    if (!options.ast and !options.pp and !options.bc) {
        const code = try compile.compileStmts(allocator, sx);
        defer allocator.free(code);

        var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator, std.io.getStdOut()));
        defer m.deinit();

        try m.run(code);
    }
}

fn mainInteractive(allocator: Allocator) !void {
    const stdout = std.io.getStdOut();
    var stdoutwr = stdout.writer();
    var ttyconf = std.io.tty.detectConfig(stdout);
    const stdin = std.io.getStdIn();
    var stdinbuf = std.io.bufferedReader(stdin.reader());
    var stdinrd = stdinbuf.reader();

    try ttyconf.setColor(stdoutwr, .bright_cyan);
    try stdoutwr.writeAll("Ava BASIC\n");
    try ttyconf.setColor(stdoutwr, .reset);

    var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator, stdout));
    defer m.deinit();

    while (true) {
        // TODO: readline(-like).
        try ttyconf.setColor(stdoutwr, .reset);
        try stdout.writeAll("> ");
        try ttyconf.setColor(stdoutwr, .bold);
        try stdout.sync();

        const inp = try stdinrd.readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse
            break;
        defer allocator.free(inp);

        try ttyconf.setColor(stdoutwr, .reset);

        var errorloc: loc.Loc = .{};
        const sx = parse.parse(allocator, inp, &errorloc) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorCaret(errorloc, stdoutwr);
            try std.fmt.format(stdoutwr, "parse: {s}\n\n", .{@errorName(err)});
            continue;
        };
        defer parse.free(allocator, sx);

        if (options.pp) {
            const out = try print.print(allocator, sx);
            defer allocator.free(out);

            try ttyconf.setColor(stdoutwr, .blue);
            try stdout.writeAll(out);
            try ttyconf.setColor(stdoutwr, .reset);
            try stdout.sync();
        }

        if (options.ast) {
            try ttyconf.setColor(stdoutwr, .green);
            for (sx) |s|
                try s.formatAst(0, stdout.writer());
            try ttyconf.setColor(stdoutwr, .reset);
            try stdout.sync();
        }

        const code = compile.compileStmts(allocator, sx) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorCaret(errorloc, stdoutwr);
            try std.fmt.format(stdoutwr, "compile: {s}\n\n", .{@errorName(err)});
            continue;
        };
        defer allocator.free(code);

        if (options.bc)
            try xxd(code);

        m.run(code) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try std.fmt.format(stdoutwr, "run error: {s}\n\n", .{@errorName(err)});
            continue;
        };
    }

    try ttyconf.setColor(stdoutwr, .reset);
    try stdout.writeAll("\ngoobai\n");
}

fn showErrorCaret(errorloc: loc.Loc, writer: anytype) !void {
    if (errorloc.row == 0) return;

    try writer.writeByteNTimes(' ', errorloc.col + 1);
    try writer.writeAll("^-- ");
}

fn xxd(code: []const u8) !void {
    var stdout = std.io.getStdOut();
    var writer = stdout.writer();
    var ttyconf = std.io.tty.detectConfig(stdout);

    var i: usize = 0;

    while (i < code.len) : (i += 16) {
        try ttyconf.setColor(writer, .white);
        try std.fmt.format(writer, "{x:0>4}:", .{i});
        const c = @min(code.len - i, 16);
        for (0..c) |j| {
            const ch = code[i + j];
            if (j % 2 == 0)
                try writer.writeByte(' ');
            if (ch < 32 or ch > 126)
                try ttyconf.setColor(writer, .bright_yellow)
            else
                try ttyconf.setColor(writer, .bright_green);
            try std.fmt.format(writer, "{x:0>2}", .{ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try writer.writeByte(' ');
            try writer.writeAll("  ");
        }

        try writer.writeAll("  ");
        for (0..c) |j| {
            const ch = code[i + j];
            if (ch < 32 or ch > 126) {
                try ttyconf.setColor(writer, .bright_yellow);
                try writer.writeByte('.');
            } else {
                try ttyconf.setColor(writer, .bright_green);
                try writer.writeByte(ch);
            }
        }

        try writer.writeByte('\n');
    }

    try ttyconf.setColor(writer, .reset);
}

const RunEffects = struct {
    const Self = @This();
    const Writer = std.io.GenericWriter(*Self, std.fs.File.WriteError, writerFn);

    allocator: Allocator,
    out: std.fs.File,
    outwr: Writer,
    col: usize = 1,

    pub fn init(allocator: Allocator, out: std.fs.File) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .out = out,
            .outwr = Writer{ .context = self },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn writerFn(self: *Self, m: []const u8) std.fs.File.WriteError!usize {
        for (m) |c| {
            if (c == '\n') {
                self.col = 1;
            } else {
                self.col += 1;
                if (self.col == 81)
                    self.col = 80;
            }
        }
        try self.out.writeAll(m);
        try self.out.sync();
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.printFormat(self.outwr, v);
    }

    // XXX: deduplicate with TestEffects pls.
    pub fn printComma(self: *Self) !void {
        // QBASIC splits the textmode screen up into 14 character "print zones".
        // Comma advances to the next, ensuring at least one space is included.
        // i.e. print zones start at column 1, 15, 29, 43, 57, 71.
        // If you're at columns 1-13 and print a comma, you'll wind up at column
        // 15. Columns 14-27 advance to 29. (14 included because 14 advancing to
        // 15 wouldn't leave a space.)
        // Why do arithmetic when just writing it out will do?
        // TODO: this won't hold up for wider screens :)
        const spaces =
            if (self.col < 14)
            15 - self.col
        else if (self.col < 28)
            29 - self.col
        else if (self.col < 42)
            43 - self.col
        else if (self.col < 56)
            57 - self.col
        else if (self.col < 70)
            71 - self.col
        else {
            try self.outwr.writeByte('\n');
            return;
        };

        try self.outwr.writeByteNTimes(' ', spaces);
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.outwr.writeByte('\n');
    }
};
