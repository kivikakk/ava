from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .core import Core
from .spifr import SPIFlashReader


__all__ = ["Top"]


class Top(wiring.Component):
    def __init__(self, platform):
        if isinstance(platform, cxxrtl):
            super().__init__({
                "uart_rx": In(1),
                "uart_tx": Out(1),

                "running": Out(1),

                "spifr_addr_stb_p": Out(24),
                "spifr_addr_stb_valid": Out(1),
                "spifr_addr_stb_ready": In(1),

                "spifr_stop_stb_valid": Out(1),
                "spifr_stop_stb_ready": In(1),

                "spifr_res_p": In(8),
                "spifr_res_valid": In(1),
            })
        else:
            super().__init__({})

    def elaborate(self, platform):
        m = Module()

        rst = Signal()
        m.d.sync += rst.eq(0)

        core = Core()

        match platform:
            case icebreaker():
                core._uart = platform.request("uart")

                btn = platform.request("button")
                with m.If(btn.i):
                    m.d.sync += rst.eq(1)

                m.submodules.spifr = spifr = ResetInserter(rst)(SPIFlashReader())
                wiring.connect(m, wiring.flipped(spifr), core.spifr_bus)

            case cxxrtl():
                core._uart = cxxrtl.Uart(
                    rx=cxxrtl.Uart.Pin(i=self.uart_rx),
                    tx=cxxrtl.Uart.Pin(o=self.uart_tx))

                m.d.comb += self.running.eq(core.running)

                m.d.comb += [
                    self.spifr_addr_stb_p.eq         (core.spifr_bus.addr_stb.p),
                    self.spifr_addr_stb_valid.eq     (core.spifr_bus.addr_stb.valid),
                    core.spifr_bus.addr_stb.ready.eq (self.spifr_addr_stb_ready),

                    self.spifr_stop_stb_valid.eq     (core.spifr_bus.stop_stb.valid),
                    core.spifr_bus.stop_stb.ready.eq (self.spifr_stop_stb_ready),

                    core.spifr_bus.res.p.eq          (self.spifr_res_p),
                    core.spifr_bus.res.valid.eq      (self.spifr_res_valid),
                ]

        m.submodules.core = ResetInserter(rst)(EnableInserter(core.running)(core))

        return m
