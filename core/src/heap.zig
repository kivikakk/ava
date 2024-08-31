const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const allocator = Allocator{
    .ptr = undefined,
    .vtable = &allocator_vtable,
};

const allocator_vtable = Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
};

pub const HeapSize = 64 * 1024;
var heap: [HeapSize]u8 align(4) = undefined;
var heap_initialized = false;

pub var heap_free: usize = HeapSize - AllocationHeaderSize;

const AllocationHeader = packed struct(u24) {
    const Self = @This();

    size: u21,
    log2_align: u2,
    occupied: bool,

    fn bufPtr(self: *align(1) const Self) [*]u8 {
        var p: usize = @intFromPtr(self) + AllocationHeaderSize;

        const MASK: u3 = switch (self.log2_align) {
            0 => 0b000,
            1 => 0b001,
            2 => 0b011,
            3 => 0b111,
        };
        while (p & MASK != 0) : (p += 1) {}

        return @ptrFromInt(p);
    }

    fn next(self: *align(1) const Self) ?*align(1) Self {
        var ix: usize = @intFromPtr(self) - @intFromPtr(heap[0..]);
        ix += self.size + AllocationHeaderSize;
        if (ix >= HeapSize - AllocationHeaderSize) {
            return null;
        }
        return @ptrCast(heap[ix..]);
    }
};

const AllocationHeaderSize = 3;

fn reinitialize_heap() void {
    const ptr: *align(1) AllocationHeader = @ptrCast(heap[0..]);
    ptr.* = .{
        .size = HeapSize - AllocationHeaderSize,
        .log2_align = 0,
        .occupied = false,
    };
    heap_initialized = true;
}

fn alloc(
    _: *anyopaque,
    len: usize,
    log2_ptr_align: u8,
    ret_addr: usize,
) ?[*]u8 {
    _ = ret_addr;

    if (!heap_initialized)
        reinitialize_heap();

    const MASK: u3 = switch (log2_ptr_align) {
        0 => 0b000,
        1 => 0b001,
        2 => 0b011,
        3 => 0b111,
        else => @panic("align greater than 8"),
    };

    var ptr: *align(1) AllocationHeader = @ptrCast(heap[0..]);

    var result: [*]u8 = undefined;
    var needed: usize = undefined;
    while (true) : (ptr = ptr.next() orelse return null) {
        if (!ptr.occupied) {
            var p = @intFromPtr(ptr.bufPtr());
            needed = len;
            while (p & MASK != 0) {
                p += 1;
                needed += 1;
            }
            if (ptr.size >= needed) {
                ptr.occupied = true;
                ptr.log2_align = @intCast(log2_ptr_align);
                result = ptr.bufPtr();
                break;
            }
        }
    }

    if (ptr.size - needed > AllocationHeaderSize) {
        const old_size = ptr.size;
        ptr.size = @intCast(needed);

        heap_free -= ptr.size + AllocationHeaderSize;

        const nextPtr = ptr.next().?;
        nextPtr.* = .{
            .size = @intCast(old_size - ptr.size - AllocationHeaderSize),
            .log2_align = 0,
            .occupied = false,
        };
    } else {
        heap_free -= ptr.size;
    }

    return result;
}

fn resize(
    _: *anyopaque,
    buf: []u8,
    log2_old_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    _ = log2_old_align;
    _ = ret_addr;

    if (new_len <= buf.len)
        return true;

    return false;
}

fn free(
    _: *anyopaque,
    buf: []u8,
    log2_old_align: u8,
    ret_addr: usize,
) void {
    _ = ret_addr;

    // XXX: this is very slow. If we don't want to do this, we need to change
    // how we handle aligned allocations entirely, since right now any induced
    // alignment causes the header to not be at (&buf-3).
    var ptr: *align(1) AllocationHeader = @ptrCast(heap[0..]);
    while (true) : (ptr = ptr.next() orelse @panic("invalid free")) {
        if (@as([*]u8, @ptrCast(buf)) == ptr.bufPtr()) {
            break;
        }
    }

    std.debug.assert(ptr.occupied);
    std.debug.assert(ptr.log2_align == log2_old_align);
    ptr.occupied = false;
    ptr.log2_align = 0;

    heap_free += ptr.size;

    ptr = @ptrCast(heap[0..]);
    while (ptr.next()) |nextPtr| {
        if (!ptr.occupied and !nextPtr.occupied) {
            heap_free += AllocationHeaderSize;
            ptr.size += AllocationHeaderSize + nextPtr.size;
        } else {
            ptr = nextPtr;
        }
    }
}

fn expectHeap(comptime layout: anytype) !void {
    const Expectation = struct {
        // Specify "occupied" and any of {"log2_align", "before", "after"}, or "free".
        occupied: ?[]const u8 = null,
        log2_align: ?u2 = null,
        before: ?usize = null,
        after: ?usize = null,

        free: ?usize = null,
    };

    var eptr: ?*align(1) AllocationHeader = @ptrCast(heap[0..]);
    inline for (layout) |o| {
        const ptr = eptr.?;
        const e = @as(Expectation, o);
        if (e.occupied) |bs| {
            std.debug.assert(e.free == null);
            try testing.expect(ptr.occupied);
            const size = (e.before orelse 0) + bs.len + (e.after orelse 0);
            try testing.expectEqual(e.log2_align orelse 0, ptr.log2_align);
            try testing.expectEqual(size, ptr.size);
            try testing.expectEqualSlices(u8, bs, ptr.bufPtr()[0..bs.len]);
        } else {
            std.debug.assert(e.before == null);
            std.debug.assert(e.after == null);
            std.debug.assert(e.log2_align == null);
            const size = e.free.?;
            try testing.expect(!ptr.occupied);
            try testing.expect(ptr.log2_align == 0);
            try testing.expectEqual(size, ptr.size);
        }

        eptr = ptr.next();
    }

    try testing.expectEqual(null, eptr);
}

test "alloc and free" {
    reinitialize_heap();
    try expectHeap(.{
        .{ .free = 65533 },
    });

    const s = try allocator.alloc(u8, 5);
    @memcpy(s, "tere!");

    try expectHeap(.{
        .{ .occupied = "tere!" },
        .{ .free = 65525 },
    });

    allocator.free(s);
    try expectHeap(.{
        .{ .free = 65533 },
    });
}

test "alloc and free and ..." {
    reinitialize_heap();
    try expectHeap(.{
        .{ .free = 65533 },
    });

    const s = try allocator.alloc(u8, 5);
    @memcpy(s, "tere!");

    const t = try allocator.alloc(u8, 8);
    @memcpy(t, "tervist!");

    try expectHeap(.{
        .{ .occupied = "tere!" },
        .{ .occupied = "tervist!" },
        .{ .free = 65514 },
    });

    allocator.free(s);
    try expectHeap(.{
        .{ .free = 5 },
        .{ .occupied = "tervist!" },
        .{ .free = 65514 },
    });

    {
        const u = try allocator.alloc(u8, 2);
        @memcpy(u, ":)");

        try expectHeap(.{
            .{ .occupied = ":)", .after = 3 },
            .{ .occupied = "tervist!" },
            .{ .free = 65514 },
        });

        allocator.free(u);
    }

    {
        const u = try allocator.alloc(u8, 3);
        @memcpy(u, ":))");

        try expectHeap(.{
            .{ .occupied = ":))", .after = 2 },
            .{ .occupied = "tervist!" },
            .{ .free = 65514 },
        });

        allocator.free(u);
    }

    {
        const u = try allocator.alloc(u8, 4);
        @memcpy(u, ":)))");

        try expectHeap(.{
            .{ .occupied = ":)))", .after = 1 },
            .{ .occupied = "tervist!" },
            .{ .free = 65514 },
        });

        allocator.free(u);
    }

    {
        const u = try allocator.alloc(u8, 1);
        @memcpy(u, "!");

        try expectHeap(.{
            .{ .occupied = "!" },
            .{ .free = 1 },
            .{ .occupied = "tervist!" },
            .{ .free = 65514 },
        });

        allocator.free(u);
    }

    allocator.free(t);

    try expectHeap(.{
        .{ .free = 65533 },
    });
}

test "alloc aligned" {
    reinitialize_heap();
    try expectHeap(.{
        .{ .free = 65533 },
    });

    // Displace alignment for following allocation. (3+3+3=9)
    const a = try allocator.alloc(u8, 3);
    @memcpy(a, "<!>");

    try expectHeap(.{
        .{ .occupied = "<!>" },
        .{ .free = 65527 },
    });

    std.debug.assert(@alignOf(u32) == 4);
    const b: []u32 = @alignCast(try allocator.alloc(u32, 1));
    b[0] = 0xaabbccdd;

    try expectHeap(.{
        .{ .occupied = "<!>" },
        .{ .occupied = "\xdd\xcc\xbb\xaa", .log2_align = 2, .before = 3 },
        .{ .free = 65517 },
    });
}

test "alloc fuzz" {
    reinitialize_heap();

    const Allo = union(enum) {
        one: []u8,
        two: []u16,
        four: []u32,
        eight: []u64,
    };

    var allocations = std.ArrayList(Allo).init(testing.allocator);
    defer allocations.deinit();

    var r = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    var random = r.random();

    for (0..1000) |_| {
        switch (random.enumValue(enum { one, two, four, eight, free })) {
            .one => {
                const v = allocator.alloc(u8, random.uintLessThan(usize, 100)) catch continue;
                try allocations.append(.{ .one = v });
            },
            .two => {
                const v = allocator.alloc(u16, random.uintLessThan(usize, 80)) catch continue;
                try allocations.append(.{ .two = v });
            },
            .four => {
                const v = allocator.alloc(u32, random.uintLessThan(usize, 70)) catch continue;
                try allocations.append(.{ .four = v });
            },
            .eight => {
                const v = allocator.alloc(u64, random.uintLessThan(usize, 200)) catch continue;
                try allocations.append(.{ .eight = v });
            },
            .free => if (allocations.items.len > 0) {
                const ix = random.uintLessThan(usize, allocations.items.len);
                switch (allocations.orderedRemove(ix)) {
                    inline else => |p| allocator.free(p),
                }
            },
        }
    }
}
