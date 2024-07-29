const std = @import("std");
const Allocator = std.mem.Allocator;

const loc = @import("loc.zig");
const WithRange = loc.WithRange;

pub const Op = enum {
    mul,
    div,
    add,
    sub,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    @"and",
    @"or",
    xor,
};

pub const ExprPayload = union(enum) {
    const Self = @This();

    imm_number: isize,
    imm_string: []const u8,
    label: []const u8,
    binop: struct {
        lhs: *Expr,
        op: WithRange(Op),
        rhs: *Expr,
    },
    // This doesn't need to exist at all, except right now our pretty-printer
    // doesn't know when an expression needs to be parenthesised/it does if we
    // want to preserve the user's formatting. AST CST blahST DST
    paren: *Expr,
    negate: *Expr,

    pub fn formatAst(self: Self, indent: usize, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            .imm_number => |n| try std.fmt.format(writer, "Number({d})\n", .{n}),
            .imm_string => |s| try std.fmt.format(writer, "String({s})\n", .{s}),
            .binop => |b| {
                try std.fmt.format(writer, "Binop({s})\n", .{@tagName(b.op.payload)});
                for (0..indent + 1) |_| try writer.writeAll("  ");
                try b.lhs.formatAst(indent + 1, writer);
                for (0..indent + 1) |_| try writer.writeAll("  ");
                try b.rhs.formatAst(indent + 1, writer);
            },
            .paren => |e| {
                try writer.writeAll("Paren\n");
                for (0..indent + 1) |_| try writer.writeAll("  ");
                try e.formatAst(indent + 1, writer);
            },
            .negate => |e| {
                try writer.writeAll("Negate\n");
                for (0..indent + 1) |_| try writer.writeAll("  ");
                try e.formatAst(indent + 1, writer);
            },
            else => unreachable,
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .imm_number => {},
            .imm_string => {},
            .label => {},
            .binop => |b| {
                b.lhs.deinit(allocator);
                b.rhs.deinit(allocator);
                allocator.destroy(b.lhs);
                allocator.destroy(b.rhs);
            },
            .paren, .negate => |e| {
                e.deinit(allocator);
                allocator.destroy(e);
            },
        }
    }

    pub fn deinitAll(allocator: Allocator, ex: []const Expr) void {
        for (ex) |e| e.deinit(allocator);
        allocator.free(ex);
    }
};

pub const Expr = WithRange(ExprPayload);

pub const StmtPayload = union(enum) {
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

    pub fn formatAst(self: Self, indent: usize, writer: anytype) !void {
        for (0..indent) |_| try writer.writeAll("  ");

        switch (self) {
            .remark => |r| try std.fmt.format(writer, "Remark: <{s}>\n", .{r}),
            .call => |c| {
                try std.fmt.format(writer, "Call <{s}> with {d} argument(s):\n", .{ c.name.payload, c.args.len });
                for (c.args, 0..) |a, i| {
                    for (0..indent + 1) |_| try writer.writeAll("  ");
                    try std.fmt.format(writer, "{d}: ", .{i});
                    try a.formatAst(indent + 1, writer);
                }
            },
            .print => |p| {
                try std.fmt.format(writer, "Print with {d} argument(s):\n", .{p.args.len});
                for (p.args, 0..) |a, i| {
                    for (0..indent + 1) |_| try writer.writeAll("  ");
                    try std.fmt.format(writer, "{d}: ", .{i});
                    try a.formatAst(indent + 1, writer);
                    if (i < p.args.len - 1) {
                        for (0..indent + 1) |_| try writer.writeAll("  ");
                        try std.fmt.format(writer, "separated by '{c}'\n", .{p.separators[i].payload});
                    }
                }
            },
            else => unreachable,
        }
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        switch (self) {
            .remark => {},
            .call => |c| Expr.deinitAll(allocator, c.args),
            .print => |p| {
                Expr.deinitAll(allocator, p.args);
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
        }
    }
};

pub const Stmt = WithRange(StmtPayload);
