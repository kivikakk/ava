const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const tokenize = @import("token.zig").tokenize;

pub const Imm = union(enum) {
    number: isize,
};

pub const Node = struct {
    value: union(enum) {
        call: struct {
            name: []const u8,
            args: []const Imm,
        },
    },
};

pub const Error = error{
    UnexpectedToken,
};

const State = union(enum) {
    init,
    label: []const u8,
};

pub fn parse(allocator: std.mem.Allocator, s: []const u8) ![]Node {
    var nx = std.ArrayList(Node).init(allocator);
    errdefer nx.deinit();

    const tx = try tokenize(allocator, s);
    defer allocator.free(tx);

    var state: State = .init;
    var i: usize = 0;
    while (i < tx.len) : (i += 1) {
        const t = tx[i];
        switch (state) {
            .init => {
                switch (t) {
                    .label => |l| state = .{ .label = l },
                    else => return Error.UnexpectedToken,
                }
            },
            .label => |l| {
                switch (t) {
                    .linefeed, .semicolon => {
                        try nx.append(.{
                            .value = .{ .call = .{
                                .name = l,
                                .args = &.{},
                            } },
                        });
                    },
                    else => return Error.UnexpectedToken,
                }
            },
        }
    }

    return nx.toOwnedSlice();
}

test "parses a nullary statement without line-number" {
    const nx = try parse(testing.allocator, "PRINT\n");
    defer testing.allocator.free(nx);

    try testing.expectEqualDeep(nx, &[_]Node{
        .{
            .value = .{ .call = .{
                .name = "PRINT",
                .args = &.{},
            } },
        },
    });
}
