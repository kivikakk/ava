const std = @import("std");
const Cxxrtl = @import("zxxrtl");

const SpiFlashConnector = @This();

const ROM = @embedFile("avacore.bin");
const ROM_BASE = 0x0080_0000;

const COUNTDOWN_BETWEEN_BYTES = 2;

req_p_addr: Cxxrtl.Object(u24),
req_p_len: Cxxrtl.Object(u16),
req_valid: Cxxrtl.Object(bool),
req_ready: Cxxrtl.Object(bool),
res_p: Cxxrtl.Object(u8),
res_valid: Cxxrtl.Object(bool),

state: enum { idle, read },
address: u24,
remaining: u16,
countdown: u8,

pub fn init(cxxrtl: Cxxrtl) SpiFlashConnector {
    const req_p_addr = cxxrtl.get(u24, "spifr_req_p_addr");
    const req_p_len = cxxrtl.get(u16, "spifr_req_p_len");
    const req_valid = cxxrtl.get(bool, "spifr_req_valid");
    const req_ready = cxxrtl.get(bool, "spifr_req_ready");
    const res_p = cxxrtl.get(u8, "spifr_res_p");
    const res_valid = cxxrtl.get(bool, "spifr_res_valid");

    req_ready.next(true);

    return .{
        .req_p_addr = req_p_addr,
        .req_p_len = req_p_len,
        .req_valid = req_valid,
        .req_ready = req_ready,
        .res_p = res_p,
        .res_valid = res_valid,

        .state = .idle,
        .address = 0,
        .remaining = 0,
        .countdown = 0,
    };
}

pub fn tick(self: *SpiFlashConnector) void {
    self.res_valid.next(false);

    switch (self.state) {
        .idle => {
            if (self.req_valid.curr()) {
                self.address = self.req_p_addr.curr();
                self.remaining = self.req_p_len.curr();

                std.debug.assert(self.remaining % 4 == 0);

                if (self.address >= ROM_BASE and self.address < ROM_BASE + ROM.len) {
                    self.req_ready.next(false);
                    self.state = .read;
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                }
            }
        },
        .read => {
            self.countdown -= 1;
            if (self.countdown == 0) {
                if (self.remaining == 0) {
                    self.req_ready.next(true);
                    self.state = .idle;
                } else {
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                    self.res_p.next(if (self.address - ROM_BASE < ROM.len) ROM[self.address - ROM_BASE] else 0xff);
                    self.res_valid.next(true);

                    self.address += 1;
                    self.remaining -= 1;
                }
            }
        },
    }
}
