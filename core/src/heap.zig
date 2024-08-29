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

const HeapSize = 64 * 1024;
var heap: [HeapSize]u8 align(4) = [_]u8{0} ** HeapSize;
var heap_initialized = false;

const AllocationHeader = packed struct(u24) {
    size: u23,
    occupied: bool,
};
const AllocationHeaderSize = 3;

fn reinitialize_heap() void {
    const ptr: *align(1) AllocationHeader = @ptrCast(heap[0..]);
    ptr.* = .{
        .size = HeapSize - AllocationHeaderSize,
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

    // TODO: support alignment
    // std.debug.assert(log2_ptr_align <= 2); // align 1, 2, 4
    std.debug.assert(log2_ptr_align == 0);

    var ix: usize = 0;
    var ptr: *align(1) AllocationHeader = @ptrCast(heap[ix..]);

    if (!heap_initialized)
        reinitialize_heap();

    if (ptr.occupied) {
        return null;
    }
    ptr.occupied = true;
    // const old_size = ptr.size;
    // TODO: support allocating when there's been a free.
    ptr.size = @intCast(len);

    ix += AllocationHeaderSize;
    const result: [*]u8 = @ptrCast(heap[ix..]);

    ix += len;
    if (HeapSize - ix > AllocationHeaderSize) {
        ptr = @ptrCast(heap[ix..]);
        ptr.* = .{
            .size = @intCast(HeapSize - ix - AllocationHeaderSize),
            .occupied = false,
        };
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
    _ = log2_old_align;
    _ = ret_addr;

    // TODO: assert buf in heap?
    var ptr: *align(1) AllocationHeader = @ptrFromInt(@intFromPtr(buf.ptr) - 3);
    std.debug.assert(ptr.occupied);
    ptr.occupied = false;
}

test "thing" {
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
        // XXX: no amalgamating yet.
        .{ .free = 5 },
        .{ .free = 65525 },
    });
}

fn expectHeap(comptime layout: anytype) !void {
    var ix: usize = 0;
    inline for (layout) |o| {
        const hdr = @as(*align(1) const AllocationHeader, @ptrCast(heap[ix..]));
        ix += AllocationHeaderSize;
        switch (@as(union(enum) { occupied: []const u8, free: usize }, o)) {
            .occupied => |bs| {
                try testing.expectEqualDeep(AllocationHeader{ .size = bs.len, .occupied = true }, hdr.*);
                ix += bs.len;
            },
            .free => |n| {
                try testing.expectEqualDeep(AllocationHeader{ .size = n, .occupied = false }, hdr.*);
                ix += n;
            },
        }
    }
    try testing.expectEqual(HeapSize, ix);
}
