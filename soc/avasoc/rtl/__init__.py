import struct
from itertools import chain
from pathlib import Path

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .core import Core
from .spifr import SPIFlashReader


__all__ = ["Top"]


def wonk32(path):
    b = path.read_bytes()
    while len(b) % 4 != 0:
        b += b'\0'
    return list(chain.from_iterable(struct.iter_unpack('<L', b)))


core_bin = Path(__file__).parent.parent.parent.parent / "core" / "zig-out" / "bin"
DMEM = wonk32(core_bin / "avacore.dmem.bin")


class Top(wiring.Component):
    def __init__(self, platform):
        if isinstance(platform, cxxrtl):
            super().__init__({
                "uart_rx": In(1),
                "uart_tx": Out(1),

                "running": Out(1),

                "spifr_req_addr": Out(24),
                "spifr_req_len": Out(16),
                "spifr_req_stb": Out(1),
                "spifr_res_busy": In(1),
                "spifr_res_data": In(8),
                "spifr_res_valid": In(1),
            })
        else:
            super().__init__({})

    def elaborate(self, platform):
        m = Module()

        rst = Signal()
        m.d.sync += rst.eq(0)

        core = Core(dmem=DMEM)

        match platform:
            case icebreaker():
                core._uart = platform.request("uart")

                btn = platform.request("button")
                m.d.sync += rst.eq(btn.i)

                m.submodules.spifr = spifr = SPIFlashReader()
                wiring.connect(m, core.spifr_bus, spifr.bus)

            case cxxrtl():
                core._uart = cxxrtl.Uart(
                    rx=cxxrtl.Uart.Pin(i=self.uart_rx),
                    tx=cxxrtl.Uart.Pin(o=self.uart_tx))

                m.d.comb += self.running.eq(core.running)

                m.d.comb += [
                    self.spifr_req_addr.eq(core.spifr_bus.addr),
                    self.spifr_req_len.eq(core.spifr_bus.len),
                    self.spifr_req_stb.eq(core.spifr_bus.stb),
                    core.spifr_bus.busy.eq(self.spifr_res_busy),
                    core.spifr_bus.data.eq(self.spifr_res_data),
                    core.spifr_bus.valid.eq(self.spifr_res_valid),
                ]

        m.submodules.core = ResetInserter(rst)(EnableInserter(core.running)(core))

        return m
