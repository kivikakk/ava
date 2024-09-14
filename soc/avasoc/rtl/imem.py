from amaranth import *
from amaranth.lib import data, stream, wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_soc.memory import MemoryMap

from .spifr import SPIFlashReader


__all__ = ["IMem"]

class IMem(wiring.Component):
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

        with m.If(self.wb_bus.cyc & self.wb_bus.stb):
            pass

        return m

