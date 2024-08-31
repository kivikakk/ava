const std = @import("std");
const Allocator = std.mem.Allocator;
const options = @import("options");
const Cxxrtl = @import("zxxrtl");

const UartConnector = @This();

const DIVISOR = options.clock_hz / 115200;

tx: Cxxrtl.Object(bool),
tx_state: enum { idle, bit } = .idle,
tx_buffer: std.ArrayList(u8),
tx_timer: usize = 0,
tx_sr: u9 = 0,
tx_counter: u4 = 0,

rx: Cxxrtl.Sample(bool),
rx_state: enum { idle, bit } = .idle,
rx_timer: usize = 0,
rx_sr: u10 = 0,
rx_counter: u4 = 0,

const Tick = union(enum) {
    nop,
    data: u8,
};

pub fn init(allocator: Allocator, cxxrtl: Cxxrtl) UartConnector {
    const tx = cxxrtl.get(bool, "uart_rx");
    const rx = Cxxrtl.Sample(bool).init(cxxrtl, "uart_tx", true);

    return .{
        .tx = tx,
        .tx_buffer = std.ArrayList(u8).init(allocator),
        .rx = rx,
    };
}

pub fn deinit(self: UartConnector) void {
    self.tx_buffer.deinit();
}

pub fn tick(self: *UartConnector) Tick {
    const rx = self.rx.tick();

    var result: Tick = .nop;

    switch (self.tx_state) {
        .idle => {
            self.tx.next(true);
            if (self.tx_buffer.items.len > 0) {
                const item = self.tx_buffer.orderedRemove(0);

                self.tx.next(false);
                self.tx_state = .bit;
                self.tx_timer = DIVISOR;
                self.tx_sr = 0x100 | @as(u9, item);
                self.tx_counter = 0;
            }
        },
        .bit => {
            self.tx_timer -= 1;
            if (self.tx_timer == 0) {
                self.tx_timer = DIVISOR;
                self.tx.next(self.tx_sr & 1 == 1);
                self.tx_sr >>= 1;

                self.tx_counter += 1;
                if (self.tx_counter == 10) {
                    self.tx.next(true);
                    self.tx_state = .idle;
                }
            }
        },
    }

    switch (self.rx_state) {
        .idle => {
            if (!rx.curr) {
                self.rx_state = .bit;
                self.rx_timer = DIVISOR / 2;
                self.rx_sr = 0;
                self.rx_counter = 0;
            }
        },
        .bit => {
            self.rx_timer -= 1;
            if (self.rx_timer == 0) {
                self.rx_timer = DIVISOR;
                self.rx_sr = (self.rx_sr << 1) | @as(u10, @intFromBool(rx.curr));

                self.rx_counter += 1;
                if (self.rx_counter == 10) {
                    self.rx_state = .idle;

                    if ((self.rx_sr & 0x200 == 0x200) or (self.rx_sr & 0x1 == 0)) {
                        std.debug.print("UartConnector ERR\n", .{});
                    } else {
                        self.rx_sr = (self.rx_sr >> 1) & 0xff;
                        self.rx_sr =
                            (self.rx_sr & 0x80) >> 7 |
                            (self.rx_sr & 0x40) >> 5 |
                            (self.rx_sr & 0x20) >> 3 |
                            (self.rx_sr & 0x10) >> 1 |
                            (self.rx_sr & 0x08) << 1 |
                            (self.rx_sr & 0x04) << 3 |
                            (self.rx_sr & 0x02) << 5 |
                            (self.rx_sr & 0x01) << 7;
                        result = .{ .data = @intCast(self.rx_sr) };
                    }
                }
            }
        },
    }

    return result;
}
