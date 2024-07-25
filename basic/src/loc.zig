const std = @import("std");

pub const Loc = struct {
    row: usize,
    col: usize,

    pub fn back(self: Loc) Loc {
        std.debug.assert(self.col > 1);
        return .{ .row = self.row, .col = self.col - 1 };
    }
};

pub const Range = struct {
    start: Loc,
    end: Loc,
};

pub fn WithRange(comptime T: type) type {
    return struct {
        const Self = @This();

        payload: T,
        range: Range,

        pub fn init(t: T, range: Range) Self {
            return .{
                .payload = t,
                .range = range,
            };
        }

        pub fn initEnds(t: T, r1: Range, r2: Range) Self {
            return init(t, .{ .start = r1.start, .end = r2.end });
        }

        pub fn initRange(t: T, start: struct { usize, usize }, end: struct { usize, usize }) Self {
            return init(t, .{
                .start = .{ .row = start[0], .col = start[1] },
                .end = .{ .row = end[0], .col = end[1] },
            });
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            // XXX: usingnamespace (if (T == u8) struct { ... }) hacks used to
            // make this compile-time verifiable. Mis nüüd?
            if (@hasDecl(T, "deinit"))
                self.payload.deinit(allocator)
            else
                @panic("deinit called but payload type " ++ @typeName(T) ++ " doesn't have one");
        }

        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try std.fmt.format(writer, "<{d}:{d}-{d}:{d}> {any}", .{
                self.range.start.row,
                self.range.start.col,
                self.range.end.row,
                self.range.end.col,
                self.payload,
            });
        }
    };
}
