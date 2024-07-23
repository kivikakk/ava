const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const token = @import("token.zig");
const WithRange = token.WithRange;

pub const Expr = union(enum) {
    imm_number: isize,
    label: []const u8,
};

pub const Stmt = union(enum) {
    const Self = @This();

    call: struct {
        name: WithRange([]const u8),
        args: []const WithRange(Expr),
    },

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .call => |c| allocator.free(c.args),
        }
    }
};

pub const Line = union(enum) {
    const Self = @This();

    stmt: Stmt,

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .stmt => |s| s.deinit(allocator),
        }
    }
};

pub const Error = error{
    UnexpectedToken,
    UnexpectedEnd,
    OutOfRange,
};

const State = union(enum) {
    init,
    call: struct {
        label: WithRange([]const u8),
        args: std.ArrayList(WithRange(Expr)),
        comma_next: bool,
    },

    fn deinit(self: State) void {
        switch (self) {
            .init => {},
            .call => |c| {
                c.args.deinit();
            },
        }
    }
};

const Parser = struct {
    const Self = @This();

    fn attach(self: *Self, stmt: Stmt) Line {
        _ = self;
        return .{ .stmt = stmt };
    }

    fn parse(self: *Self, allocator: Allocator, s: []const u8) ![]Line {
        var lx = std.ArrayList(Line).init(allocator);
        errdefer lx.deinit();

        const tx = try token.tokenize(allocator, s);
        defer allocator.free(tx);

        var state: State = .init;
        defer state.deinit();

        var i: usize = 0;
        while (i < tx.len) : (i += 1) {
            const t = tx[i];
            switch (state) {
                .init => {
                    switch (t.payload) {
                        .label => |l| state = .{ .call = .{
                            .label = WithRange([]const u8).init(l, t.range),
                            .args = std.ArrayList(WithRange(Expr)).init(allocator),
                            .comma_next = false,
                        } },
                        .linefeed => {},
                        else => return Error.UnexpectedToken,
                    }
                },
                .call => |*c| {
                    switch (t.payload) {
                        .linefeed, .semicolon => {
                            try lx.append(self.attach(.{
                                .call = .{
                                    .name = c.label,
                                    .args = try c.args.toOwnedSlice(),
                                },
                            }));
                            state = .init;
                        },
                        .comma => {
                            if (!c.comma_next)
                                return Error.UnexpectedToken;
                            c.comma_next = false;
                        },
                        .number => |n| {
                            if (c.comma_next)
                                return Error.UnexpectedToken;
                            try c.args.append(.{
                                .payload = .{ .imm_number = n },
                                .range = t.range,
                            });
                            c.comma_next = true;
                        },
                        .label => |l| {
                            if (c.comma_next)
                                return Error.UnexpectedToken;
                            try c.args.append(.{
                                .payload = .{ .label = l },
                                .range = t.range,
                            });
                            c.comma_next = true;
                        },
                        else => return Error.UnexpectedToken,
                    }
                },
            }
        }

        switch (state) {
            .init => {},
            .call => |*c| {
                if (!c.comma_next and c.args.items.len > 0)
                    // File ends at "BLAH X,"
                    return Error.UnexpectedEnd;
                try lx.append(self.attach(.{
                    .call = .{
                        .name = c.label,
                        .args = try c.args.toOwnedSlice(),
                    },
                }));
            },
        }

        return lx.toOwnedSlice();
    }
};

pub fn parse(allocator: Allocator, s: []const u8) ![]Line {
    var p = Parser{};
    return p.parse(allocator, s);
}

test "parses a nullary statement" {
    const lx = try parse(testing.allocator, "PRINT\n");
    defer testing.allocator.free(lx);

    try testing.expectEqualDeep(lx, &[_]Line{
        .{ .stmt = .{
            .call = .{
                .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
                .args = &.{},
            },
        } },
    });
}

test "parses a nullary statement without linefeed" {
    const lx = try parse(testing.allocator, "PRINT");
    defer testing.allocator.free(lx);

    try testing.expectEqualDeep(lx, &[_]Line{
        .{ .stmt = .{
            .call = .{
                .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
                .args = &.{},
            },
        } },
    });
}

test "parses a unary statement" {
    const lx = try parse(testing.allocator, "\n PRINT 42\n");
    defer {
        for (lx) |l| l.deinit(testing.allocator);
        testing.allocator.free(lx);
    }

    try testing.expectEqualDeep(lx, &[_]Line{
        .{ .stmt = .{
            .call = .{
                .name = WithRange([]const u8).initRange("PRINT", .{ 2, 2 }, .{ 2, 6 }),
                .args = &.{
                    WithRange(Expr).initRange(.{ .imm_number = 42 }, .{ 2, 8 }, .{ 2, 9 }),
                },
            },
        } },
    });
}

test "parses a binary statement" {
    const lx = try parse(testing.allocator, "PRINT X$, Y%\n");
    defer {
        for (lx) |l| l.deinit(testing.allocator);
        testing.allocator.free(lx);
    }

    try testing.expectEqualDeep(lx, &[_]Line{
        .{ .stmt = .{
            .call = .{
                .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
                .args = &.{
                    WithRange(Expr).initRange(.{ .label = "X$" }, .{ 1, 7 }, .{ 1, 8 }),
                    WithRange(Expr).initRange(.{ .label = "Y%" }, .{ 1, 11 }, .{ 1, 12 }),
                },
            },
        } },
    });
}
