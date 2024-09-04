from amaranth import *
from amaranth.lib import data, stream, wiring
from amaranth.lib.wiring import In, Out

from .spifr import SPIFlashReader


__all__ = ["IMem"]

class IMem(wiring.Component):
    cmd: Out(stream.Signature(data.StructLayout({ "address": 32, "size": 3 })))
    rsp: In(stream.Signature(data.StructLayout({ "data": 32, "error": 1 }), always_ready=True))
    spifr_bus: Out(SPIFlashReader.Signature)

    _base: int

    def __init__(self, *, base):
        super().__init__()
        self._base = base

    def elaborate(self, platform):
        m = Module()

        ix = Signal(range(32))
        m.d.sync += self.spifr_bus.req.valid.eq(0)
        m.d.sync += self.rsp.valid.eq(0)

        with m.FSM():
            with m.State('init'):
                m.d.comb += self.cmd.ready.eq(self.spifr_bus.req.ready)
                with m.If(self.cmd.ready & self.cmd.valid):
                    m.d.sync += Assert(self.cmd.p.size == 5)  # i.e. 2**5 == 32 bytes
                    m.d.sync += [
                        ix.eq(0),
                        self.spifr_bus.req.p.addr.eq(self._base + self.cmd.p.address),
                        self.spifr_bus.req.p.len.eq(32),
                        self.spifr_bus.req.valid.eq(1),
                    ]
                    m.next = 'read.wait'

            with m.State('read.wait'):
                with m.If(self.spifr_bus.res.valid):
                    with m.Switch(ix[:2]):
                        with m.Case(0):
                            m.d.sync += self.rsp.p.data[:8].eq(self.spifr_bus.res.p)
                        with m.Case(1):
                            m.d.sync += self.rsp.p.data[8:16].eq(self.spifr_bus.res.p)
                        with m.Case(2):
                            m.d.sync += self.rsp.p.data[16:24].eq(self.spifr_bus.res.p)
                        with m.Case(3):
                            m.d.sync += self.rsp.p.data[24:].eq(self.spifr_bus.res.p)
                            m.d.sync += self.rsp.valid.eq(1)
                    with m.If(ix == 31):
                        m.next = 'init'
                    with m.Else():
                        m.d.sync += ix.eq(ix + 1)
        return m

