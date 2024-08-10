const std = @import("std");
const Allocator = std.mem.Allocator;

const isa = @import("../isa.zig");
const PrintLoc = @import("../PrintLoc.zig");
const ErrorInfo = @import("../ErrorInfo.zig");

pub const helpText =
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

pub fn showErrorInfo(errorinfo: ErrorInfo, writer: anytype, lockind: enum { caret, loc }) !void {
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

pub fn xxd(code: []const u8) !void {
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
            if (ch == 0)
                try ttyconf.setColor(stdoutwr, .reset)
            else if (ch < 32 or ch > 126)
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
            if (ch == 0) {
                try ttyconf.setColor(stdoutwr, .reset);
                try stdoutwr.writeByte('.');
            } else if (ch < 32 or ch > 126) {
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

pub const RunEffects = struct {
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
        try isa.printFormat(self.allocator, self.outwr, v);
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

    pub fn pragmaPrinted(self: *Self, s: []const u8) !void {
        _ = self;
        _ = s;
        unreachable;
    }
};
