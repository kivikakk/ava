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

state: enum { idle, read },
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

    addr_stb_ready.next(true);

    return .{
        .addr_stb_p = addr_stb_p,
        .addr_stb_valid = addr_stb_valid,
        .addr_stb_ready = addr_stb_ready,
        .stop_stb_valid = stop_stb_valid,
        .stop_stb_ready = stop_stb_ready,
        .res_p = res_p,
        .res_valid = res_valid,

        .state = .idle,
        .address = 0,
        .countdown = 0,
    };
}

pub fn tick(self: *SpiFlashConnector) void {
    self.stop_stb_ready.next(false);
    self.res_valid.next(false);

    switch (self.state) {
        .idle => {
            if (self.addr_stb_valid.curr()) {
                self.address = self.addr_stb_p.curr();

                if (self.address >= ROM_BASE and self.address < ROM_BASE + ROM.len) {
                    self.addr_stb_ready.next(false);
                    self.state = .read;
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                }
            }
        },
        .read => {
            self.countdown -= 1;
            if (self.countdown == 1) {
                self.stop_stb_ready.next(true);
            } else if (self.countdown == 0) {
                if (self.stop_stb_valid.curr()) {
                    self.addr_stb_ready.next(true);
                    self.state = .idle;
                } else {
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                    self.res_p.next(if (self.address - ROM_BASE < ROM.len) ROM[self.address - ROM_BASE] else 0xff);
                    self.res_valid.next(true);

                    self.address += 1;
                }
            }
        },
    }
}
