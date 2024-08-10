const std = @import("std");
const Allocator = std.mem.Allocator;

const isa = @import("../isa.zig");
const PrintLoc = @import("../PrintLoc.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

const opts = @import("opts.zig");

const HandleRead = struct {
    const Self = @This();

    file: std.fs.File,
    br: std.io.BufferedReader(4096, std.fs.File.Reader),
    rd: std.io.BufferedReader(4096, std.fs.File.Reader).Reader,

    fn init(self: *Self, file: std.fs.File) void {
        self.file = file;
        self.br = std.io.bufferedReader(file.reader());
        self.rd = self.br.reader();
    }
};

const HandleWrite = struct {
    const Self = @This();

    file: std.fs.File,
    bw: std.io.BufferedWriter(4096, std.fs.File.Writer),
    wr: std.io.BufferedWriter(4096, std.fs.File.Writer).Writer,
    tc: std.io.tty.Config,

    fn init(self: *Self, file: std.fs.File) void {
        self.file = file;
        self.bw = std.io.bufferedWriter(file.writer());
        self.wr = self.bw.writer();
        self.tc = std.io.tty.detectConfig(file);
    }
};

pub var stdin: HandleRead = undefined;
pub var stdout: HandleWrite = undefined;
pub var stderr: HandleWrite = undefined;

pub fn handlesInit() void {
    stdin.init(std.io.getStdIn());
    stdout.init(std.io.getStdOut());
    stderr.init(std.io.getStdErr());
}

pub fn handlesDeinit() !void {
    try stderr.bw.flush();
    try stdout.bw.flush();
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

pub const Output = enum { stdout, stderr };
pub const LocKind = enum { caret, loc };

pub fn handleError(comptime what: []const u8, err: anyerror, errorinfo: ErrorInfo, output: Output, lockind: LocKind) !void {
    const bundle = switch (output) {
        .stdout => &stdout,
        .stderr => &stderr,
    };

    try bundle.tc.setColor(bundle.wr, .bright_red);

    if (errorinfo.loc) |errloc| {
        switch (lockind) {
            .caret => {
                try bundle.wr.writeByteNTimes(' ', errloc.col + 1);
                try bundle.wr.writeAll("^-- ");
            },
            .loc => try std.fmt.format(bundle.wr, "({d}:{d}) ", .{ errloc.row, errloc.col }),
        }
    }
    if (errorinfo.msg) |m| {
        try bundle.wr.writeAll(m);
        try bundle.wr.writeByte('\n');
    } else {
        try bundle.wr.writeAll("(no info)\n");
    }

    try std.fmt.format(bundle.wr, what ++ ": {s}\n\n", .{@errorName(err)});
    try bundle.tc.setColor(bundle.wr, .reset);
    try bundle.bw.flush();
}

pub fn xxd(code: []const u8) !void {
    var i: usize = 0;

    while (i < code.len) : (i += 16) {
        try stdout.tc.setColor(stdout.wr, .white);
        try std.fmt.format(stdout.wr, "{x:0>4}:", .{i});
        const c = @min(code.len - i, 16);
        for (0..c) |j| {
            const ch = code[i + j];
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            if (ch == 0)
                try stdout.tc.setColor(stdout.wr, .reset)
            else if (ch < 32 or ch > 126)
                try stdout.tc.setColor(stdout.wr, .bright_yellow)
            else
                try stdout.tc.setColor(stdout.wr, .bright_green);
            try std.fmt.format(stdout.wr, "{x:0>2}", .{ch});
        }

        for (c..16) |j| {
            if (j % 2 == 0)
                try stdout.wr.writeByte(' ');
            try stdout.wr.writeAll("  ");
        }

        try stdout.wr.writeAll("  ");
        for (0..c) |j| {
            const ch = code[i + j];
            if (ch == 0) {
                try stdout.tc.setColor(stdout.wr, .reset);
                try stdout.wr.writeByte('.');
            } else if (ch < 32 or ch > 126) {
                try stdout.tc.setColor(stdout.wr, .bright_yellow);
                try stdout.wr.writeByte('.');
            } else {
                try stdout.tc.setColor(stdout.wr, .bright_green);
                try stdout.wr.writeByte(ch);
            }
        }

        try stdout.wr.writeByte('\n');
    }

    try stdout.tc.setColor(stdout.wr, .reset);
    try stdout.bw.flush();
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
        try stdout.wr.writeAll(m);
        try stdout.bw.flush();
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
