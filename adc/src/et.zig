const std = @import("std");
const Allocator = std.mem.Allocator;

const proto = @import("avacore").proto;

pub fn EventThread(comptime Reader: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        reader: Reader,
        thread: std.Thread = undefined,
        mutex: std.Thread.Mutex = .{},
        sema: std.Thread.Semaphore = .{},

        evs: std.ArrayList(proto.Event),
        running: std.atomic.Value(bool),

        pub fn init(allocator: Allocator, reader: Reader) !*Self {
            var et = try allocator.create(Self);
            et.* = .{
                .allocator = allocator,
                .reader = reader,
                .evs = std.ArrayList(proto.Event).init(allocator),
                .running = std.atomic.Value(bool).init(true),
            };
            et.thread = try std.Thread.spawn(.{}, run, .{et});
            return et;
        }

        fn run(self: *Self) void {
            while (self.running.load(.acquire)) {
                // TODO: handle errors & communicate back.
                const ev = proto.Event.read(self.allocator, self.reader) catch |err|
                    std.debug.panic("EventThread read error: {any}", .{err});

                switch (ev) {
                    .DEBUG => |msg| {
                        std.debug.print("debug: '{s}'\n", .{msg});
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

        pub fn readWait(self: *Self) proto.Event {
            self.sema.wait();
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.evs.orderedRemove(0);
        }

        pub fn deinit(self: *Self) void {
            self.running.store(false, .release);
            // TODO: cause run()'s blocking read to abort safely.
            self.thread.join();
            for (self.evs.items) |ev|
                ev.deinit(self.allocator);
            self.evs.deinit();
            self.allocator.destroy(self);
        }
    };
}
