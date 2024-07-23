const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const token = @import("token.zig");
const WithRange = token.WithRange;

pub const Expr = union(enum) {
    imm_number: isize,
    label: []const u8,
};

pub const Node = union(enum) {
    const Self = @This();

    call: struct {
        name: WithRange([]const u8),
        args: []const WithRange(Expr),
    },

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .call => |c| {
                allocator.free(c.args);
            },
        }
    }
};

pub const Error = error{
    UnexpectedToken,
    UnexpectedEnd,
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

pub fn parse(allocator: Allocator, s: []const u8) ![]Node {
    var nx = std.ArrayList(Node).init(allocator);
    errdefer nx.deinit();

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
                        try nx.append(.{
                            .call = .{
                                .name = c.label,
                                .args = try c.args.toOwnedSlice(),
                            },
                        });
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
            try nx.append(.{
                .call = .{
                    .name = c.label,
                    .args = try c.args.toOwnedSlice(),
                },
            });
        },
    }

    return nx.toOwnedSlice();
}

test "parses a nullary statement without line-number" {
    const nx = try parse(testing.allocator, "PRINT\n");
    defer testing.allocator.free(nx);

    try testing.expectEqualDeep(nx, &[_]Node{
        .{
            .call = .{
                .name = .{
                    .payload = "PRINT",
                    .range = .{
                        .start = .{ .row = 1, .col = 1 },
                        .end = .{ .row = 1, .col = 5 },
                    },
                },
                .args = &.{},
            },
        },
    });
}

test "parses a nullary statement without line-number, without linefeed" {
    const nx = try parse(testing.allocator, "PRINT");
    defer testing.allocator.free(nx);

    try testing.expectEqualDeep(nx, &[_]Node{
        .{
            .call = .{
                .name = .{
                    .payload = "PRINT",
                    .range = .{
                        .start = .{ .row = 1, .col = 1 },
                        .end = .{ .row = 1, .col = 5 },
                    },
                },
                .args = &.{},
            },
        },
    });
}

test "parses a unary statement without line-number" {
    const nx = try parse(testing.allocator, "\n PRINT 42\n");
    defer {
        for (nx) |n| n.deinit(testing.allocator);
        testing.allocator.free(nx);
    }

    try testing.expectEqualDeep(nx, &[_]Node{
        .{
            .call = .{
                .name = .{
                    .payload = "PRINT",
                    .range = .{
                        .start = .{ .row = 2, .col = 2 },
                        .end = .{ .row = 2, .col = 6 },
                    },
                },
                .args = &.{
                    .{
                        .payload = .{ .imm_number = 42 },
                        .range = .{
                            .start = .{ .row = 2, .col = 8 },
                            .end = .{ .row = 2, .col = 9 },
                        },
                    },
                },
            },
        },
    });
}

test "parses a binary statement without line-number" {
    const nx = try parse(testing.allocator, "PRINT X$, Y%\n");
    defer {
        for (nx) |n| n.deinit(testing.allocator);
        testing.allocator.free(nx);
    }

    try testing.expectEqualDeep(nx, &[_]Node{
        .{
            .call = .{
                .name = .{
                    .payload = "PRINT",
                    .range = .{
                        .start = .{ .row = 1, .col = 1 },
                        .end = .{ .row = 1, .col = 5 },
                    },
                },
                .args = &.{
                    .{
                        .payload = .{ .label = "X$" },
                        .range = .{
                            .start = .{ .row = 1, .col = 7 },
                            .end = .{ .row = 1, .col = 8 },
                        },
                    },
                    .{
                        .payload = .{ .label = "Y%" },
                        .range = .{
                            .start = .{ .row = 1, .col = 11 },
                            .end = .{ .row = 1, .col = 12 },
                        },
                    },
                },
            },
        },
    });
}
