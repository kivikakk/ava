from amaranth import Module, Signal, Mux
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
        mem_wr = mem.write_port()
        mem_rd = mem.read_port(transparent_for=[mem_wr])

        level = Signal(range(self.depth + 1))
        delay = Signal()

        m.d.sync += [
            mem_wr.en.eq(0),
            delay.eq(0),
        ]

        w_fire = self.w_stream.ready & self.w_stream.valid
        r_fire = self.r_stream.ready & self.r_stream.valid

        m.d.comb += [
            self.w_stream.ready.eq(level != self.depth),
            self.r_stream.payload.eq(mem_rd.data),
            self.r_stream.valid.eq(~w_fire & ~delay & (level != 0)),
            mem_rd.addr.eq(Mux(level == 0, 0, level - 1)),
        ]

        with m.If(w_fire):
            m.d.sync += [
                mem_wr.addr.eq(level),
                mem_wr.data.eq(self.w_stream.payload),
                mem_wr.en.eq(1),
                level.eq(level + 1),
                delay.eq(1),
            ]

        with m.If(r_fire):
            m.d.sync += [
                level.eq(level - 1),
                delay.eq(1),
            ]

        return m
