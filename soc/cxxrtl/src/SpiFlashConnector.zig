const std = @import("std");
const Cxxrtl = @import("zxxrtl");

const SpiFlashConnector = @This();

const ROM = @embedFile("avacore.imem.bin");
const ROM_BASE = 0x0080_0000;

const COUNTDOWN_BETWEEN_BYTES = 2;

req_addr: Cxxrtl.Object(u24),
req_len: Cxxrtl.Object(u16),
req_stb: Cxxrtl.Object(bool),
res_busy: Cxxrtl.Object(bool),
res_data: Cxxrtl.Object(u8),
res_valid: Cxxrtl.Object(bool),

state: enum { idle, read },
address: u24,
remaining: u16,
countdown: u8,

pub fn init(cxxrtl: Cxxrtl) SpiFlashConnector {
    const req_addr = cxxrtl.get(u24, "spifr_req_addr");
    const req_len = cxxrtl.get(u16, "spifr_req_len");
    const req_stb = cxxrtl.get(bool, "spifr_req_stb");
    const res_busy = cxxrtl.get(bool, "spifr_res_busy");
    const res_data = cxxrtl.get(u8, "spifr_res_data");
    const res_valid = cxxrtl.get(bool, "spifr_res_valid");

    res_busy.next(false);

    return .{
        .req_addr = req_addr,
        .req_len = req_len,
        .req_stb = req_stb,
        .res_busy = res_busy,
        .res_data = res_data,
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
            if (self.req_stb.curr()) {
                self.address = self.req_addr.curr();
                self.remaining = self.req_len.curr();

                if (self.address >= ROM_BASE and self.address < ROM_BASE + ROM.len) {
                    self.res_busy.next(true);
                    self.state = .read;
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                }
            }
        },
        .read => {
            self.countdown -= 1;
            if (self.countdown == 0) {
                if (self.remaining == 0) {
                    self.res_busy.next(false);
                    self.state = .idle;
                } else {
                    self.countdown = COUNTDOWN_BETWEEN_BYTES;
                    self.res_data.next(if (self.address - ROM_BASE < ROM.len) ROM[self.address - ROM_BASE] else 0xff);
                    self.res_valid.next(true);

                    self.address += 1;
                    self.remaining -= 1;
                }
            }
        },
    }
}
