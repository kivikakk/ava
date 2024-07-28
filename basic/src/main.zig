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
    ast: bool = false,
    pp: bool = false,
    help: bool = false,
};
var options: Options = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const optionsParsed = try args.parseForCurrentProcess(Options, allocator, .print);
    defer optionsParsed.deinit();

    options = optionsParsed.options;

    if (options.help) usage(optionsParsed.executable_name, 0);
    if (optionsParsed.positionals.len > 1) usage(optionsParsed.executable_name, 1);

    if (optionsParsed.positionals.len == 1) {
        const inp = try std.fs.cwd().readFileAlloc(allocator, optionsParsed.positionals[0], 1048576);
        defer allocator.free(inp);

        if (options.ast)
            try mainAst(allocator, inp);

        if (options.pp)
            try mainPp(allocator, inp);

        if (!options.ast and !options.pp)
            try mainRun(allocator, inp);
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
        \\  --ast      When given [file], prints its AST without executing.
        \\             Otherwise, prints the AST of each input before executing.
        \\  --pp       Pretty-prints [file] without executing it.
        \\             Otherwise, pretty-prints each input before executing.
        \\  --help     Shows this information.
        \\
        \\Ava BASIC  Copyright (C) 2024  Asherah Erin Connor
        \\This program comes with ABSOLUTELY NO WARRANTY; for details type `LICENCE
        \\WARRANTY'. This is free software, and you are welcome to redistribute it
        \\under certain conditions; type `LICENCE CONDITIONS' for details.
    , .{executable_name});
    std.process.exit(status);
}

fn handleErr(err: anyerror, errorloc: loc.Loc) @TypeOf(err) {
    std.debug.print("loc: ({d}:{d})\n", .{ errorloc.row, errorloc.col });
    return err;
}

fn mainInteractive(allocator: Allocator) !void {
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();
    var stdinBuffered = std.io.bufferedReader(stdin.reader());
    var stdinReader = stdinBuffered.reader();

    var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator, stdout));
    defer m.deinit();

    while (true) {
        try stdout.writeAll("> ");
        try stdout.sync();

        const inp = try stdinReader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1048576) orelse
            break;
        defer allocator.free(inp);

        var errorloc: loc.Loc = .{};
        const sx = parse.parse(allocator, inp, &errorloc) catch |err| {
            handleErr(err, errorloc) catch {};
            std.debug.print("parse err: {any}\n\n", .{err});
            continue;
        };
        defer parse.free(allocator, sx);

        if (options.ast) {
            for (sx) |s|
                try s.formatAst(0, stdout.writer());
            try stdout.sync();
        }

        if (options.pp) {
            const out = try print.print(allocator, sx);
            defer allocator.free(out);

            try stdout.writeAll(out);
            try stdout.sync();
        }

        const code = compile.compileStmts(allocator, sx) catch |err| {
            std.debug.print("compile err: {any}\n\n", .{err});
            continue;
        };

        defer allocator.free(code);

        m.run(code) catch |err| {
            std.debug.print("run err: {any}\n\n", .{err});
            continue;
        };
    }

    std.debug.print("\ngoobai\n", .{});
}

fn mainRun(allocator: Allocator, inp: []const u8) !void {
    var errorloc: loc.Loc = .{};
    const code = compile.compile(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer allocator.free(code);

    var m = stack.Machine(*RunEffects).init(allocator, try RunEffects.init(allocator, std.io.getStdOut()));
    defer m.deinit();

    try m.run(code);
}

fn mainAst(allocator: Allocator, inp: []const u8) !void {
    var errorloc: loc.Loc = .{};
    const sx = parse.parse(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer parse.free(allocator, sx);

    const outwr = std.io.getStdOut().writer();
    for (sx) |s| {
        try s.formatAst(0, outwr);
    }
}

fn mainPp(allocator: Allocator, inp: []const u8) !void {
    var errorloc: loc.Loc = .{};
    const sx = parse.parse(allocator, inp, &errorloc) catch |err| return handleErr(err, errorloc);
    defer parse.free(allocator, sx);

    const out = try print.print(allocator, sx);
    defer allocator.free(out);

    try std.io.getStdOut().writeAll(out);
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
