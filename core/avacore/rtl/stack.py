from amaranth import Module, Signal, Mux, Print
from amaranth.lib import stream
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import Component, In, Out

__all__ = ["Stack"]


class Stack(Component):
    def __init__(self, *, width, depth):
        assert isinstance(width, int) and width >= 0
        assert isinstance(depth, int) and depth > 0

        self.width = width
        self.depth = depth

        super().__init__({
            "w_stream": In(stream.Signature(width)),
            "r_stream": Out(stream.Signature(width)),
        })

    def elaborate(self, platform):
        m = Module()

        m.submodules.mem = mem = Memory(shape=self.width, depth=self.depth, init=[])
        mem_rd = mem.read_port()
        mem_wr = mem.write_port()
        m.d.sync += mem_wr.en.eq(0)

        level = Signal(range(self.depth + 1))

        m.d.comb += self.w_stream.ready.eq(level != self.depth)
        with m.If(self.w_stream.valid):
            m.d.sync += [
                mem_wr.addr.eq(level),
                mem_wr.data.eq(self.w_stream.payload),
                mem_wr.en.eq(1),
                level.eq(level + 1),
            ]

        m.d.comb += [
            self.r_stream.payload.eq(mem_rd.data),
            mem_rd.addr.eq(Mux(level == 0, 0, level - 1)),
            self.r_stream.valid.eq(level != 0),
        ]

        with m.If(self.r_stream.ready & self.r_stream.valid):
            m.d.sync += level.eq(level - 1)
        
        return m
