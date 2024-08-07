from amaranth import Module, Signal
from amaranth.lib import wiring
from amaranth.lib.wiring import Out

from ..targets import cxxrtl, icebreaker, ulx3s

__all__ = ["Top"]


class Top(wiring.Component):
    def __init__(self, platform):
        if isinstance(platform, cxxrtl):
            super().__init__(
                {
                    "ledr": Out(1),
                    "ledg": Out(1),
                }
            )
        else:
            super().__init__({})

    def elaborate(self, platform):

        m = Module()

        m.submodules.blinker = blinker = Blinker()

        match platform:
            case icebreaker():
                m.d.comb += platform.request("led_r").o.eq(blinker.ledr)
                m.d.comb += platform.request("led_g").o.eq(blinker.ledg)

            case ulx3s():
                m.d.comb += platform.request("led", 0).o.eq(blinker.ledr)
                m.d.comb += platform.request("led", 1).o.eq(blinker.ledg)

            case cxxrtl():
                m.d.comb += self.ledr.eq(blinker.ledr)
                m.d.comb += self.ledg.eq(blinker.ledg)

        return m


class Blinker(wiring.Component):
    ledr: Out(1)
    ledg: Out(1)

    def elaborate(self, platform):
        m = Module()

        m.d.comb += self.ledg.eq(1)

        timer_top = (int(platform.default_clk_frequency) // 2) - 1
        timer_half = (int(platform.default_clk_frequency) // 4) - 1
        timer_reg = Signal(range(timer_top), init=timer_half)

        with m.If(timer_reg == 0):
            m.d.sync += [
                self.ledr.eq(~self.ledr),
                timer_reg.eq(timer_top),
            ]
        with m.Else():
            m.d.sync += timer_reg.eq(timer_reg - 1)

        return m
