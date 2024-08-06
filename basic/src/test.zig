const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Compiler = @import("Compiler.zig");
const stack = @import("stack.zig");
const ErrorInfo = @import("ErrorInfo.zig");

const Matches = struct {
    const Self = @This();

    const Entry = struct {
        path: []u8,
        contents: []u8,
    };

    entries: []Entry,

    pub fn deinit(self: Self) void {
        for (self.entries) |e| {
            testing.allocator.free(e.path);
            testing.allocator.free(e.contents);
        }
        testing.allocator.free(self.entries);
    }
};

pub fn matchingBasPaths(prefix: []const u8) !Matches {
    var out = std.ArrayListUnmanaged(Matches.Entry){};
    errdefer {
        for (out.items) |e| {
            testing.allocator.free(e.path);
            testing.allocator.free(e.contents);
        }
        out.deinit(testing.allocator);
    }

    const dir = try std.fs.cwd().openDir("src/bas", .{ .iterate = true });

    var it = dir.iterate();
    while (try it.next()) |e| {
        if (std.mem.startsWith(u8, e.name, prefix)) {
            const path = try std.fmt.allocPrint(testing.allocator, "src/bas/{s}", .{e.name});
            errdefer testing.allocator.free(path);

            const contents = try std.fs.cwd().readFileAlloc(testing.allocator, path, 1048576);
            errdefer testing.allocator.free(contents);

            try out.append(testing.allocator, .{ .path = path, .contents = contents });
        }
    }

    std.debug.assert(out.items.len > 0);

    return .{ .entries = try out.toOwnedSlice(testing.allocator) };
}

pub fn parsePragmaString(allocator: Allocator, i: []const u8) ![]u8 {
    var s = std.ArrayListUnmanaged(u8){};
    defer s.deinit(allocator);

    var state: enum { init, escape } = .init;
    for (i) |c| {
        switch (state) {
            .init => switch (c) {
                '\\' => state = .escape,
                else => try s.append(allocator, c),
            },
            .escape => {
                switch (c) {
                    'n' => try s.append(allocator, '\n'),
                    else => @panic("unhandled escape"),
                }
                state = .init;
            },
        }
    }

    std.debug.assert(state == .init);

    return s.toOwnedSlice(allocator);
}

test "functionals" {
    const matches = try matchingBasPaths("ft.");
    defer matches.deinit();

    for (matches.entries) |e|
        try testing.checkAllAllocationFailures(
            testing.allocator,
            expectFunctional,
            .{ e.path, e.contents },
        );
}

fn expectFunctional(allocator: Allocator, path: []const u8, contents: []const u8) !void {
    var errorinfo: ErrorInfo = .{};
    const code = Compiler.compileText(allocator, contents, &errorinfo) catch |err| {
        if (err == error.OutOfMemory)
            return err;
        std.debug.panic("err {any} in FT '{s}' at {any}", .{ err, path, errorinfo });
    };
    defer allocator.free(code);

    var m = stack.Machine(stack.TestEffects).init(allocator, try stack.TestEffects.init(), null);
    defer m.deinit();

    try m.run(code);

    var fail = false;
    for (m.effects.expectations.items) |e|
        if (!std.mem.eql(u8, e.exp, e.act)) {
            fail = true;
            break;
        };

    if (fail)
        for (m.effects.expectations.items) |e| {
            if (std.mem.eql(u8, e.exp, e.act)) {
                std.debug.print("match: \"{s}\"\n\n", .{std.mem.trimRight(u8, e.exp, "\r\n")});
            } else {
                fail = true;
                std.debug.print("exp.:  \"{s}\" !!\nact.:  \"{s}\" !!\n\n", .{
                    std.mem.trimRight(u8, e.exp, "\r\n"),
                    std.mem.trimRight(u8, e.act, "\r\n"),
                });
            }
        };

    try testing.expect(!fail);
}
