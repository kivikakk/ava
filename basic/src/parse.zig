const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const token = @import("token.zig");
const WithRange = token.WithRange;

pub const Expr = union(enum) {
    imm_number: isize,
    imm_string: []const u8,
    label: []const u8,
};

pub const Stmt = union(enum) {
    const Self = @This();

    call: struct {
        name: WithRange([]const u8),
        args: []const WithRange(Expr),
    },
    remark: WithRange([]const u8),

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .call => |c| allocator.free(c.args),
            .remark => {},
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

    allocator: Allocator,
    tx: []token.Token,
    nti: usize,

    fn init(allocator: Allocator, inp: []const u8) !Self {
        const tx = try token.tokenize(allocator, inp);
        return .{
            .allocator = allocator,
            .tx = tx,
            .nti = 0,
        };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.tx);
    }

    fn eoi(self: *const Self) bool {
        return self.nti == self.tx.len;
    }

    fn nt(self: *const Self) ?token.Token {
        if (self.eoi())
            return null;
        return self.tx[self.nti];
    }

    fn accept(self: *Self, comptime tt: token.TokenTag) ?WithRange(std.meta.TagPayload(token.TokenPayload, tt)) {
        const t = self.nt() orelse return null;
        if (t.payload == tt) {
            self.nti += 1;
            const payload = @field(t.payload, @tagName(tt));
            return WithRange(std.meta.TagPayload(token.TokenPayload, tt)).init(payload, t.range);
        }
        return null;
    }

    fn parseOne(self: *Self) !?Stmt {
        if (self.eoi())
            return null;

        if (self.accept(.linefeed)) |_|
            return self.parseOne();

        if (self.accept(.label)) |l| {
            if (self.eoi() or self.accept(.linefeed) != null) {
                return .{ .call = .{
                    .name = l,
                    .args = &.{},
                } };
            }
            return error.NYILabel;
        }
        return error.NYIParseOne;
    }

    fn parseAll(self: *Self) ![]Stmt {
        var sx = std.ArrayList(Stmt).init(self.allocator);
        errdefer sx.deinit();

        while (try self.parseOne()) |s| {
            try sx.append(s);
        }

        return sx.toOwnedSlice();
    }

    // fn parse(self: *Self) ![]Stmt {
    //     var sx = std.ArrayList(Stmt).init(self.allocator);
    //     errdefer sx.deinit();

    //     const tx = try token.tokenize(allocator, inp);
    //     defer allocator.free(tx);

    //     var state: State = .init;
    //     defer state.deinit();

    //     var i: usize = 0;
    //     while (i < tx.len) : (i += 1) {
    //         const t = tx[i];
    //         self.t = t;

    //         if (t.payload == .remark) {
    //             try sx.append(self.attach(.{
    //                 .remark = WithRange([]const u8).init(t.payload.remark, t.range),
    //             }));
    //             continue;
    //         }

    //         switch (state) {
    //             .init => {
    //                 switch (t.payload) {
    //                     .label => |s| state = .{ .call = .{
    //                         .label = WithRange([]const u8).init(s, t.range),
    //                         .args = std.ArrayList(WithRange(Expr)).init(allocator),
    //                         .comma_next = false,
    //                     } },
    //                     .kw_let => state = .{ .let = .{} },
    //                     .linefeed => {},
    //                     else => return Error.UnexpectedToken,
    //                 }
    //             },
    //             .call => |*c| {
    //                 switch (t.payload) {
    //                     .linefeed, .semicolon => {
    //                         try sx.append(self.attach(.{
    //                             .call = .{
    //                                 .name = c.label,
    //                                 .args = try c.args.toOwnedSlice(),
    //                             },
    //                         }));
    //                         state = .init;
    //                     },
    //                     .comma => {
    //                         if (!c.comma_next)
    //                             return Error.UnexpectedToken;
    //                         c.comma_next = false;
    //                     },
    //                     .number => |n| {
    //                         if (c.comma_next)
    //                             return Error.UnexpectedToken;
    //                         try c.args.append(.{
    //                             .payload = .{ .imm_number = n },
    //                             .range = t.range,
    //                         });
    //                         c.comma_next = true;
    //                     },
    //                     .label => |s| {
    //                         if (c.comma_next)
    //                             return Error.UnexpectedToken;
    //                         try c.args.append(.{
    //                             .payload = .{ .label = s },
    //                             .range = t.range,
    //                         });
    //                         c.comma_next = true;
    //                     },
    //                     .string => |s| {
    //                         if (c.comma_next)
    //                             return Error.UnexpectedToken;
    //                         try c.args.append(.{
    //                             .payload = .{ .imm_string = s },
    //                             .range = t.range,
    //                         });
    //                         c.comma_next = true;
    //                     },
    //                     else => return Error.UnexpectedToken,
    //                 }
    //             },
    //         }
    //     }

    //     switch (state) {
    //         .init => {},
    //         .call => |*c| {
    //             if (!c.comma_next and c.args.items.len > 0)
    //                 // File ends at "BLAH X,"
    //                 return Error.UnexpectedEnd;
    //             try sx.append(self.attach(.{
    //                 .call = .{
    //                     .name = c.label,
    //                     .args = try c.args.toOwnedSlice(),
    //                 },
    //             }));
    //         },
    //     }

    //     return sx.toOwnedSlice();
    // }
};

pub fn parse(allocator: Allocator, inp: []const u8) ![]Stmt {
    var p = try Parser.init(allocator, inp);
    defer p.deinit();

    return p.parseAll() catch |err| {
        // TODO: show last/next token
        // std.debug.print("last token: {any}\n", .{p.t});
        return err;
    };
}

pub fn freeStmts(allocator: Allocator, sx: []Stmt) void {
    for (sx) |s| s.deinit(allocator);
    allocator.free(sx);
}

test "parses a nullary statement" {
    const sx = try parse(testing.allocator, "PRINT\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        },
    }});
}

test "parses a nullary statement without linefeed" {
    const sx = try parse(testing.allocator, "PRINT");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{},
        },
    }});
}

test "parses a unary statement" {
    const sx = try parse(testing.allocator, "\n PRINT 42\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 2, 2 }, .{ 2, 6 }),
            .args = &.{
                WithRange(Expr).initRange(.{ .imm_number = 42 }, .{ 2, 8 }, .{ 2, 9 }),
            },
        },
    }});
}

test "parses a binary statement" {
    const sx = try parse(testing.allocator, "PRINT X$, Y%\n");
    defer freeStmts(testing.allocator, sx);

    try testing.expectEqualDeep(sx, &[_]Stmt{.{
        .call = .{
            .name = WithRange([]const u8).initRange("PRINT", .{ 1, 1 }, .{ 1, 5 }),
            .args = &.{
                WithRange(Expr).initRange(.{ .label = "X$" }, .{ 1, 7 }, .{ 1, 8 }),
                WithRange(Expr).initRange(.{ .label = "Y%" }, .{ 1, 11 }, .{ 1, 12 }),
            },
        },
    }});
}

test "testpp/01.bas" {
    const inp = try std.fs.cwd().readFileAlloc(testing.allocator, "src/testpp/01.bas", 1048576);
    defer testing.allocator.free(inp);

    const sx = try parse(testing.allocator, inp);
    defer freeStmts(testing.allocator, sx);
}
