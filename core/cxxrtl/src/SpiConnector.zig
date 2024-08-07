const std = @import("std");
const Cxxrtl = @import("zxxrtl");

const SpiConnector = @This();

cipo: Cxxrtl.Object(bool),
dc: Cxxrtl.Sample(bool),
res: Cxxrtl.Sample(bool),
copi: Cxxrtl.Sample(bool),
clk: Cxxrtl.Sample(bool),

sr: u8 = 0,
index: u8 = 0,

const Tick = union(enum) {
    Nop,
    Command: u8,
    Data: u8,
};

pub fn init(cxxrtl: Cxxrtl) SpiConnector {
    const cipo = cxxrtl.get(bool, "lcd__cipo");
    const dc = Cxxrtl.Sample(bool).init(cxxrtl, "lcd__dc", false);
    const res = Cxxrtl.Sample(bool).init(cxxrtl, "lcd_res", false);
    const copi = Cxxrtl.Sample(bool).init(cxxrtl, "lcd__copi", false);
    const clk = Cxxrtl.Sample(bool).init(cxxrtl, "lcd__clk", false);

    return .{
        .cipo = cipo,
        .dc = dc,
        .res = res,
        .copi = copi,
        .clk = clk,
    };
}

pub fn tick(self: *SpiConnector) Tick {
    const dc = self.dc.tick();
    const res = self.res.tick();
    const copi = self.copi.tick();
    const clk = self.clk.tick();

    var result: Tick = .Nop;

    if (res.curr) {
        self.sr = 0;
        self.index = 0;
    }

    if (clk.rising()) {
        self.sr = (self.sr << 1) | @as(u8, (if (copi.curr) 1 else 0));
        if (self.index < 7)
            self.index += 1
        else if (dc.curr) {
            result = .{ .Command = self.sr };
            self.index = 0;
        } else {
            result = .{ .Data = self.sr };
            self.index = 0;
        }
    }

    return result;
}
