const std = @import("std");
const Allocator = std.mem.Allocator;
const args = @import("args");

const loc = @import("loc.zig");
const Loc = loc.Loc;
const Parser = @import("Parser.zig");
const print = @import("print.zig");
const isa = @import("isa.zig");
const Compiler = @import("Compiler.zig");
const stack = @import("stack.zig");
const PrintLoc = @import("PrintLoc.zig");
const ErrorInfo = @import("ErrorInfo.zig");

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
    const stdout = std.io.getStdOut();
    var stdoutbw = std.io.bufferedWriter(stdout.writer());
    const stdoutwr = stdoutbw.writer();
    var ttyconf = std.io.tty.detectConfig(stdout);

    const inp = try std.fs.cwd().readFileAlloc(allocator, filename, 1048576);
    defer allocator.free(inp);

    var errorinfo: ErrorInfo = .{};
    const sx = Parser.parse(allocator, inp, &errorinfo) catch |err| {
        try ttyconf.setColor(stdoutwr, .bright_red);
        try showErrorInfo(errorinfo, stdoutwr, .loc);
        try std.fmt.format(stdoutwr, "parse: {s}\n\n", .{@errorName(err)});
        try stdoutbw.flush();
        return err;
    };
    defer Parser.free(allocator, sx);

    if (options.pp) {
        const out = try print.print(allocator, sx);
        defer allocator.free(out);

        try stdoutwr.writeAll(out);
    }

    if (options.ast) {
        for (sx) |s|
            try s.formatAst(0, stdoutwr);
    }

    if (options.bc) {
        const code = Compiler.compile(allocator, sx, &errorinfo) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorInfo(errorinfo, stdoutwr, .loc);
            try std.fmt.format(stdoutwr, "compile: {s}\n\n", .{@errorName(err)});
            try stdoutbw.flush();
            return err;
        };
        defer allocator.free(code);

        try stdoutbw.flush();
        try xxd(code);
    }

    if (!options.ast and !options.pp and !options.bc) {
        const code = Compiler.compile(allocator, sx, &errorinfo) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorInfo(errorinfo, stdoutwr, .loc);
            try std.fmt.format(stdoutwr, "compile: {s}\n\n", .{@errorName(err)});
            try stdoutbw.flush();
            return err;
        };
        defer allocator.free(code);

        var m = stack.Machine(RunEffects).init(allocator, try RunEffects.init(allocator, stdout), &errorinfo);
        defer m.deinit();

        try stdoutbw.flush();

        m.run(code) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorInfo(errorinfo, stdoutwr, .loc);
            try std.fmt.format(stdoutwr, "run error: {s}\n\n", .{@errorName(err)});
            try stdoutbw.flush();
            return err;
        };
    }
}

fn mainInteractive(allocator: Allocator) !void {
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

    var m = stack.Machine(RunEffects).init(allocator, try RunEffects.init(allocator, stdout), &errorinfo);
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
            try showErrorInfo(errorinfo, stdoutwr, .caret);
            try std.fmt.format(stdoutwr, "parse: {s}\n\n", .{@errorName(err)});
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
            try stdoutbw.flush();
        }

        const code = c.compileStmts(sx) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorInfo(errorinfo, stdoutwr, .caret);
            try std.fmt.format(stdoutwr, "compile: {s}\n\n", .{@errorName(err)});
            continue;
        };
        defer allocator.free(code);

        if (options.bc)
            try xxd(code);

        m.run(code) catch |err| {
            try ttyconf.setColor(stdoutwr, .bright_red);
            try showErrorInfo(errorinfo, stdoutwr, .loc);
            try std.fmt.format(stdoutwr, "run error: {s}\n\n", .{@errorName(err)});
            continue;
        };
    }

    try ttyconf.setColor(stdoutwr, .reset);
    try stdoutwr.writeAll("\ngoobai\n");
    try stdoutbw.flush();
}

fn showErrorInfo(errorinfo: ErrorInfo, writer: anytype, lockind: enum { caret, loc }) !void {
    if (errorinfo.loc) |errloc| {
        switch (lockind) {
            .caret => {
                try writer.writeByteNTimes(' ', errloc.col + 1);
                try writer.writeAll("^-- ");
            },
            .loc => try std.fmt.format(writer, "({d}:{d}) ", .{ errloc.row, errloc.col }),
        }
    }
    if (errorinfo.msg) |m| {
        try writer.writeAll(m);
        try writer.writeByte('\n');
    } else {
        try writer.writeAll("(no info)\n");
    }
}

fn xxd(code: []const u8) !void {
    const stdout = std.io.getStdOut();
    var stdoutbw = std.io.bufferedWriter(stdout.writer());
    const stdoutwr = stdoutbw.writer();
    var ttyconf = std.io.tty.detectConfig(stdout);

    var i: usize = 0;

    while (i < code.len) : (i += 16) {
        try ttyconf.setColor(stdoutwr, .white);
        try std.fmt.format(stdoutwr, "{x:0>4}:", .{i});
        const c = @min(code.len - i, 16);
        for (0..c) |j| {
            const ch = code[i + j];
            if (j % 2 == 0)
                try stdoutwr.writeByte(' ');
            if (ch < 32 or ch > 126)
                try ttyconf.setColor(stdoutwr, .bright_yellow)
            else
                try ttyconf.setColor(stdoutwr, .bright_green);
            try std.fmt.format(stdoutwr, "{x:0>2}", .{ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try stdoutwr.writeByte(' ');
            try stdoutwr.writeAll("  ");
        }

        try stdoutwr.writeAll("  ");
        for (0..c) |j| {
            const ch = code[i + j];
            if (ch < 32 or ch > 126) {
                try ttyconf.setColor(stdoutwr, .bright_yellow);
                try stdoutwr.writeByte('.');
            } else {
                try ttyconf.setColor(stdoutwr, .bright_green);
                try stdoutwr.writeByte(ch);
            }
        }

        try stdoutwr.writeByte('\n');
    }

    try ttyconf.setColor(stdoutwr, .reset);
    try stdoutbw.flush();
}

const RunEffects = struct {
    const Self = @This();
    pub const Error = std.fs.File.WriteError;
    const Writer = std.io.GenericWriter(*Self, std.fs.File.WriteError, writerFn);

    allocator: Allocator,
    out: std.fs.File,
    outwr: Writer,
    printloc: PrintLoc = .{},

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
        self.printloc.write(m);
        try self.out.writeAll(m);
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.printFormat(self.outwr, v);
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try self.outwr.writeByte('\n'),
            .spaces => |s| try self.outwr.writeByteNTimes(' ', s),
        }
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.outwr.writeByte('\n');
    }
};
