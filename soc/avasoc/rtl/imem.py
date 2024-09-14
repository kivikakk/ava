from amaranth import *
from amaranth.lib import data, stream, wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_soc.memory import MemoryMap

from .spifr import SPIFlashReader


__all__ = ["WishboneIMem"]

class WishboneIMem(wiring.Component):
    wb_bus: In(wishbone.bus.Signature(addr_width=18, data_width=32,
                                      granularity=8, features={"err", "cti", "bte"}))
    spifr_bus: Out(SPIFlashReader.Signature)

    _base: int

    def __init__(self, *, base):
        self._base = base
        super().__init__()

        self.wb_bus.memory_map = MemoryMap(addr_width=20, data_width=8)
        # TODO: add_resource I guess.
        self.wb_bus.memory_map.freeze()

    def elaborate(self, platform):
        m = Module()

        byte_no = Signal(range(4))

        with m.FSM():
            with m.State('idle'):
                with m.If(self.wb_bus.ack):
                    m.d.sync += self.wb_bus.ack.eq(0)
                with m.Elif(self.wb_bus.cyc & self.wb_bus.stb):
                    m.d.comb += self.spifr_bus.addr_stb.p.eq(self._base | (self.wb_bus.adr << 2))
                    m.d.comb += self.spifr_bus.addr_stb.valid.eq(1)
                    with m.If(self.spifr_bus.addr_stb.ready):
                        m.d.sync += Print(Format("WishboneIMem: self.wb_bus.adr: {:06x}", self._base | (self.wb_bus.adr << 2)))
                        m.d.sync += byte_no.eq(0)
                        m.next = 'await'

            with m.State('await'):
                with m.If(self.spifr_bus.res.valid):
                    m.d.sync += byte_no.eq(byte_no + 1)
                    with m.Switch(byte_no):
                        with m.Case(0):
                            m.d.sync += self.wb_bus.dat_r[:8].eq(self.spifr_bus.res.p)
                        with m.Case(1):
                            m.d.sync += self.wb_bus.dat_r[8:16].eq(self.spifr_bus.res.p)
                        with m.Case(2):
                            m.d.sync += self.wb_bus.dat_r[16:24].eq(self.spifr_bus.res.p)
                        with m.Case(3):
                            m.d.sync += self.wb_bus.dat_r[24:].eq(self.spifr_bus.res.p)
                            m.d.sync += self.wb_bus.ack.eq(1)
                            m.next = 'stop'

            with m.State('stop'):
                with m.If(self.wb_bus.ack):
                    m.d.sync += Print(Format("WishboneIMem: yielded: {:08x}", self.wb_bus.dat_r))
                    m.d.sync += self.wb_bus.ack.eq(0)
                m.d.comb += self.spifr_bus.stop_stb.valid.eq(1)
                with m.If(self.spifr_bus.stop_stb.ready):
                    m.d.sync += Print(Format("WishboneIMem: back to idle"))
                    m.next = 'idle'

        return m

