const std = @import("std");
const Allocator = std.mem.Allocator;

const loc = @import("../loc.zig");
const Range = loc.Range;
const WithRange = loc.WithRange;
const Expr = @import("Expr.zig");

const Stmt = @This();

payload: Payload,
range: Range,

pub fn init(payload: Payload, range: Range) Stmt {
    return .{ .payload = payload, .range = range };
}

pub fn deinit(self: Stmt, allocator: Allocator) void {
    self.payload.deinit(allocator);
}

pub fn formatAst(self: Stmt, indent: usize, writer: anytype) !void {
    try self.payload.formatAst(indent, writer);
}

pub const Payload = union(enum) {
    const Self = @This();

    remark: []const u8,
    call: struct {
        name: WithRange([]const u8),
        args: []const Expr,
    },
    print: struct {
        args: []const Expr,
        separators: []const WithRange(u8),
    },
    let: struct {
        kw: bool,
        lhs: WithRange([]const u8),
        tok_eq: WithRange(void),
        rhs: Expr,
    },
    @"if": struct {
        cond: Expr,
        tok_then: WithRange(void),
    },
    if1: struct {
        cond: Expr,
        tok_then: WithRange(void),
        stmt_t: *Stmt,
    },
    if2: struct {
        cond: Expr,
        tok_then: WithRange(void),
        stmt_t: *Stmt,
        tok_else: WithRange(void),
        stmt_f: *Stmt,
    },
    @"for": struct {
        lv: WithRange([]const u8),
        tok_eq: WithRange(void),
        from: Expr,
        tok_to: WithRange(void),
        to: Expr,
    },
    forstep: struct {
        lv: WithRange([]const u8),
        tok_eq: WithRange(void),
        from: Expr,
        tok_to: WithRange(void),
        to: Expr,
        tok_step: WithRange(void),
        step: Expr,
    },
    next: WithRange([]const u8),
    jumplabel: []const u8,
    goto: WithRange([]const u8),
    end,
    endif,
    pragma_printed: WithRange([]const u8),

    pub fn formatAst(self: Self, indent: usize, writer: anytype) !void {
        try writer.writeBytesNTimes("  ", indent);

        switch (self) {
            .remark => |r| try std.fmt.format(writer, "Remark: <{s}>\n", .{r}),
            .call => |c| {
                try std.fmt.format(writer, "Call <{s}> with {d} argument(s):\n", .{ c.name.payload, c.args.len });
                for (c.args, 0..) |a, i| {
                    try writer.writeBytesNTimes("  ", indent + 1);
                    try std.fmt.format(writer, "{d}: ", .{i});
                    try a.formatAst(indent + 1, writer);
                }
                try writer.writeByte('\n');
            },
            .print => |p| {
                try std.fmt.format(writer, "Print with {d} argument(s):\n", .{p.args.len});
                for (p.args, 0..) |a, i| {
                    try writer.writeBytesNTimes("  ", indent + 1);
                    try std.fmt.format(writer, "{d}: ", .{i});
                    try a.formatAst(indent + 1, writer);
                    if (i < p.separators.len) {
                        try writer.writeBytesNTimes("  ", indent + 1);
                        try std.fmt.format(writer, "separated by '{c}'", .{p.separators[i].payload});
                    }
                    try writer.writeByte('\n');
                }
            },
            .let => |l| {
                try std.fmt.format(writer, "Let <{s}>:\n", .{l.lhs.payload});
                try writer.writeBytesNTimes("  ", indent + 1);
                try l.rhs.payload.formatAst(indent + 1, writer);
                try writer.writeByte('\n');
            },
            else => unreachable,
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .remark => {},
            .call => |c| Expr.deinitSlice(allocator, c.args),
            .print => |p| {
                Expr.deinitSlice(allocator, p.args);
                allocator.free(p.separators);
            },
            .let => |l| l.rhs.deinit(allocator),
            .@"if" => |i| i.cond.deinit(allocator),
            .if1 => |i| {
                i.cond.deinit(allocator);
                i.stmt_t.deinit(allocator);
                allocator.destroy(i.stmt_t);
            },
            .if2 => |i| {
                i.cond.deinit(allocator);
                i.stmt_t.deinit(allocator);
                allocator.destroy(i.stmt_t);
                i.stmt_f.deinit(allocator);
                allocator.destroy(i.stmt_f);
            },
            .@"for" => |f| {
                f.from.deinit(allocator);
                f.to.deinit(allocator);
            },
            .forstep => |f| {
                f.from.deinit(allocator);
                f.to.deinit(allocator);
                f.step.deinit(allocator);
            },
            .next => {},
            .jumplabel => {},
            .goto => {},
            .end => {},
            .endif => {},
            .pragma_printed => {},
        }
    }
};
