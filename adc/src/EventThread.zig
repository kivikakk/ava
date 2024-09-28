const std = @import("std");
const Allocator = std.mem.Allocator;

const proto = @import("avacore").proto;

const EventThread = @This();

allocator: Allocator,
reader: std.io.AnyReader,
handle: std.posix.fd_t,
thread: std.Thread = undefined,
mutex: std.Thread.Mutex = .{},
sema: std.Thread.Semaphore = .{},

evs: std.ArrayList(proto.Event),
running: std.atomic.Value(bool),

pub fn init(allocator: Allocator, reader: std.io.AnyReader, handle: std.posix.fd_t) !*EventThread {
    var et = try allocator.create(EventThread);
    et.* = .{
        .allocator = allocator,
        .reader = reader,
        .handle = handle,
        .evs = std.ArrayList(proto.Event).init(allocator),
        .running = std.atomic.Value(bool).init(true),
    };
    et.thread = try std.Thread.spawn(.{}, run, .{et});
    return et;
}

fn run(self: *EventThread) void {
    while (self.running.load(.acquire)) {
        // TODO: handle errors & communicate back.
        const ev = proto.Event.read(self.allocator, self.reader) catch |err| switch (err) {
            error.NotOpenForReading, error.EndOfStream => return,
            else => std.debug.panic("EventThread read error: {any}", .{err}),
        };

        switch (ev) {
            .DEBUG => |msg| {
                std.debug.print("{s}", .{msg});
                ev.deinit(self.allocator);
                continue;
            },
            else => {},
        }

        {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.evs.append(ev) catch |err|
                std.debug.panic("EventThread append error: {any}", .{err});
        }
        self.sema.post();
    }
}

pub fn readWait(self: *EventThread) proto.Event {
    self.sema.wait();
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.evs.orderedRemove(0);
}

pub fn deinit(self: *EventThread) void {
    self.running.store(false, .release);
    std.posix.close(self.handle);
    self.thread.join();
    for (self.evs.items) |ev|
        ev.deinit(self.allocator);
    self.evs.deinit();
    self.allocator.destroy(self);
}
