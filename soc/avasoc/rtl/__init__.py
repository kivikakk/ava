import struct
from itertools import chain
from pathlib import Path

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .core import Core


__all__ = ["Top"]


def wonk32(path):
    b = path.read_bytes()
    while len(b) % 4 != 0:
        b += b'\0'
    return list(chain.from_iterable(struct.iter_unpack('<L', b)))


core_bin = Path(__file__).parent.parent.parent.parent / "core" / "zig-out" / "bin"
# Our vexriscv will always read one past a jump; CXXRTL will abort on an out-of-bounds read.
IMEM = wonk32(core_bin / "avacore.imem.bin") + [0]
DMEM = wonk32(core_bin / "avacore.dmem.bin")


class Top(wiring.Component):
    def __init__(self, platform):
        if isinstance(platform, cxxrtl):
            super().__init__({
                "uart_rx": In(1),
                "uart_tx": Out(1),
                "running": Out(1),
            })
        else:
            super().__init__({})

    def elaborate(self, platform):
        m = Module()

        rst = Signal()
        m.d.sync += rst.eq(0)

        running = Signal()

        match platform:
            case icebreaker():
                uart = platform.request("uart")

                btn = platform.request("button")
                with m.If(btn.i):
                    m.d.sync += rst.eq(1)

            case cxxrtl():
                uart = cxxrtl.Uart(
                    rx=cxxrtl.Uart.Pin(i=self.uart_rx),
                    tx=cxxrtl.Uart.Pin(o=self.uart_tx))
                m.d.comb += self.running.eq(running)

        core = Core(imem=IMEM, dmem=DMEM, uart=uart)
        m.d.comb += running.eq(core.running)
        m.submodules.core = ResetInserter(rst)(EnableInserter(running)(core))

        return m
