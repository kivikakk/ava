const std = @import("std");
const Allocator = std.mem.Allocator;

const isa = @import("../isa.zig");
const PrintLoc = @import("../PrintLoc.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");

pub const Output = enum { stdout, stderr };
pub var stdin: std.fs.File = undefined;
pub var stdinBr: std.io.BufferedReader(4096, std.fs.File.Reader) = undefined;
pub var stdinRd: @TypeOf(stdinBr).Reader = undefined;
pub var stdout: std.fs.File = undefined;
pub var stdoutBw: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;
pub var stdoutWr: @TypeOf(stdoutBw).Writer = undefined;
pub var stdoutTc: std.io.tty.Config = undefined;
pub var stderr: std.fs.File = undefined;
pub var stderrBw: std.io.BufferedWriter(4096, std.fs.File.Writer) = undefined;
pub var stderrWr: @TypeOf(stderrBw).Writer = undefined;
pub var stderrTc: std.io.tty.Config = undefined;

pub fn handlesInit() void {
    stdin = std.io.getStdIn();
    stdinBr = std.io.bufferedReader(stdin.reader());
    stdinRd = stdinBr.reader();

    stdout = std.io.getStdOut();
    stdoutBw = std.io.bufferedWriter(stdout.writer());
    stdoutWr = stdoutBw.writer();
    stdoutTc = std.io.tty.detectConfig(stdout);

    stderr = std.io.getStdErr();
    stderrBw = std.io.bufferedWriter(stderr.writer());
    stderrWr = stderrBw.writer();
    stderrTc = std.io.tty.detectConfig(stderr);
}

pub fn handlesDeinit() !void {
    try stderrBw.flush();
    try stdoutBw.flush();
}

const helpText =
    \\
    \\Global options:
    \\
    \\  -h, --help     Show command-specific usage
    \\
    \\Ava BASIC  Copyright (C) 2024  Asherah Erin Connor
    \\This program comes with ABSOLUTELY NO WARRANTY; for details type `LICENCE
    \\WARRANTY'. This is free software, and you are welcome to redistribute it
    \\under certain conditions; type `LICENCE CONDITIONS' for details.
    \\
;

pub fn usageFor(status: u8, comptime command: []const u8, comptime argsPart: []const u8, comptime body: []const u8) noreturn {
    std.debug.print(
    //    12345678901234567890123456789012345678901234567890123456789012345678901234567890
        \\Usage: {?s} 
    ++ command ++ (if (argsPart.len > 0) " " else "") ++ argsPart ++ "\n\n" ++
        body ++ helpText, .{opts.global.executable_name});
    std.process.exit(status);
}

pub const RunMode = enum { bas, avc };
pub fn runModeFromFilename(filename: []const u8) ?RunMode {
    return if (std.ascii.endsWithIgnoreCase(filename, ".bas"))
        .bas
    else if (std.ascii.endsWithIgnoreCase(filename, ".avc"))
        .avc
    else
        null;
}

pub const LocKind = enum { caret, loc };

pub fn handleError(comptime what: []const u8, err: anyerror, errorinfo: ErrorInfo, output: Output, lockind: LocKind) !void {
    const handles: struct {
        bw: *std.io.BufferedWriter(4096, std.fs.File.Writer),
        wr: std.io.BufferedWriter(4096, std.fs.File.Writer).Writer,
        tc: std.io.tty.Config,
    } = switch (output) {
        .stdout => .{ .bw = &stdoutBw, .wr = stdoutWr, .tc = stdoutTc },
        .stderr => .{ .bw = &stderrBw, .wr = stderrWr, .tc = stderrTc },
    };

    try handles.tc.setColor(handles.wr, .bright_red);

    if (errorinfo.loc) |errloc| {
        switch (lockind) {
            .caret => {
                try handles.wr.writeByteNTimes(' ', errloc.col + 1);
                try handles.wr.writeAll("^-- ");
            },
            .loc => try std.fmt.format(handles.wr, "({d}:{d}) ", .{ errloc.row, errloc.col }),
        }
    }
    if (errorinfo.msg) |m| {
        try handles.wr.writeAll(m);
        try handles.wr.writeByte('\n');
    } else {
        try handles.wr.writeAll("(no info)\n");
    }

    try std.fmt.format(handles.wr, what ++ ": {s}\n\n", .{@errorName(err)});
    try handles.tc.setColor(handles.wr, .reset);
    try handles.bw.flush();
}

pub fn xxd(code: []const u8) !void {
    var i: usize = 0;

    while (i < code.len) : (i += 16) {
        try stdoutTc.setColor(stdoutWr, .white);
        try std.fmt.format(stdoutWr, "{x:0>4}:", .{i});
        const c = @min(code.len - i, 16);
        for (0..c) |j| {
            const ch = code[i + j];
            if (j % 2 == 0)
                try stdoutWr.writeByte(' ');
            if (ch == 0)
                try stdoutTc.setColor(stdoutWr, .reset)
            else if (ch < 32 or ch > 126)
                try stdoutTc.setColor(stdoutWr, .bright_yellow)
            else
                try stdoutTc.setColor(stdoutWr, .bright_green);
            try std.fmt.format(stdoutWr, "{x:0>2}", .{ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try stdoutWr.writeByte(' ');
            try stdoutWr.writeAll("  ");
        }

        try stdoutWr.writeAll("  ");
        for (0..c) |j| {
            const ch = code[i + j];
            if (ch == 0) {
                try stdoutTc.setColor(stdoutWr, .reset);
                try stdoutWr.writeByte('.');
            } else if (ch < 32 or ch > 126) {
                try stdoutTc.setColor(stdoutWr, .bright_yellow);
                try stdoutWr.writeByte('.');
            } else {
                try stdoutTc.setColor(stdoutWr, .bright_green);
                try stdoutWr.writeByte(ch);
            }
        }

        try stdoutWr.writeByte('\n');
    }

    try stdoutTc.setColor(stdoutWr, .reset);
    try stdoutBw.flush();
}

pub const RunEffects = struct {
    const Self = @This();
    pub const Error = std.fs.File.WriteError;
    const Writer = std.io.GenericWriter(*Self, std.fs.File.WriteError, writerFn);

    allocator: Allocator,
    writer: Writer,
    printloc: PrintLoc = .{},

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .writer = Writer{ .context = self },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn writerFn(self: *Self, m: []const u8) std.fs.File.WriteError!usize {
        self.printloc.write(m);
        try stdoutWr.writeAll(m);
        try stdoutBw.flush();
        return m.len;
    }

    pub fn print(self: *Self, v: isa.Value) !void {
        try isa.printFormat(self.allocator, self.writer, v);
    }

    pub fn printComma(self: *Self) !void {
        switch (self.printloc.comma()) {
            .newline => try self.writer.writeByte('\n'),
            .spaces => |s| try self.writer.writeByteNTimes(' ', s),
        }
    }

    pub fn printLinefeed(self: *Self) !void {
        try self.writer.writeByte('\n');
    }

    pub fn pragmaPrinted(self: *Self, s: []const u8) !void {
        _ = self;
        _ = s;
        unreachable;
    }
};
