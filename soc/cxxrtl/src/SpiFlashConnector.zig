const std = @import("std");
const Cxxrtl = @import("zxxrtl");

const SpiFlashConnector = @This();

const ROM = @embedFile("avacore.bin");
const ROM_BASE = 0x0080_0000;

const COUNTDOWN_BETWEEN_BYTES = 2;

addr_stb_p: Cxxrtl.Object(u24),
addr_stb_valid: Cxxrtl.Object(bool),
addr_stb_ready: Cxxrtl.Object(bool),
stop_stb_valid: Cxxrtl.Object(bool),
stop_stb_ready: Cxxrtl.Object(bool),
res_p: Cxxrtl.Object(u8),
res_valid: Cxxrtl.Object(bool),

state: enum { powerdown_release, cmd_wait, read },
stopping: bool,
address: u24,
countdown: u8,

pub fn init(cxxrtl: Cxxrtl) SpiFlashConnector {
    const addr_stb_p = cxxrtl.get(u24, "spifr_addr_stb_p");
    const addr_stb_valid = cxxrtl.get(bool, "spifr_addr_stb_valid");
    const addr_stb_ready = cxxrtl.get(bool, "spifr_addr_stb_ready");
    const stop_stb_valid = cxxrtl.get(bool, "spifr_stop_stb_valid");
    const stop_stb_ready = cxxrtl.get(bool, "spifr_stop_stb_ready");
    const res_p = cxxrtl.get(u8, "spifr_res_p");
    const res_valid = cxxrtl.get(bool, "spifr_res_valid");

    return .{
        .addr_stb_p = addr_stb_p,
        .addr_stb_valid = addr_stb_valid,
        .addr_stb_ready = addr_stb_ready,
        .stop_stb_valid = stop_stb_valid,
        .stop_stb_ready = stop_stb_ready,
        .res_p = res_p,
        .res_valid = res_valid,

        .state = .powerdown_release,
        .stopping = true,
        .address = 0,
        .countdown = 8,
    };
}

pub fn tick(self: *SpiFlashConnector) void {
    if (!self.stopping and self.stop_stb_valid.curr()) {
        // std.debug.print("SpiFlashConnector: got stop signal\n", .{});
        self.stopping = true;
    }
    self.stop_stb_ready.next(!self.stopping);

    self.res_valid.next(false);

    switch (self.state) {
        .powerdown_release => {
            self.countdown -= 1;
            if (self.countdown == 0) {
                // std.debug.print("SpiFlashConnector: setting addr_stb_ready\n", .{});
                self.addr_stb_ready.next(true);
                self.state = .cmd_wait;
            }
        },
        .cmd_wait => {
            if (self.addr_stb_valid.curr()) {
                self.address = self.addr_stb_p.curr();
                // std.debug.print("SpiFlashConnector: got address: {x:0>6}\n", .{self.address});
                // std.debug.print("SpiFlashConnector: addr_stb_ready is {}\n", .{self.addr_stb_ready.curr()});

                if (self.address >= ROM_BASE and self.address < ROM_BASE + ROM.len) {
                    // std.debug.print("SpiFlashConnector: lowering stb\n", .{});
                    self.addr_stb_ready.next(false);
                    self.state = .read;
                    self.stopping = false;
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                }
            }
        },
        .read => {
            self.countdown -= 1;
            if (self.countdown == 0) {
                self.countdown = COUNTDOWN_BETWEEN_BYTES;
                self.res_p.next(if (self.address - ROM_BASE < ROM.len) ROM[self.address - ROM_BASE] else 0xff);
                self.res_valid.next(true);

                self.address += 1;

                if (self.stop_stb_valid.curr()) {
                    // std.debug.print("SpiFlashConnector: stopping\n", .{});
                    self.addr_stb_ready.next(true);
                    self.state = .cmd_wait;
                }
            }
        },
    }
}
