from amaranth import *
from amaranth.lib import stream, data
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import Component, In, Out


__all__ = ["ImemInterface", "ImemMemory"]


class ImemInterface(Component):
    class Command(data.Struct):
        "Only one command for now: set PC."
        pc: 16

    def __init__(self, *, depth):
        super().__init__({
            "insn_stream": Out(stream.Signature(8)),
            "pc": Out(range(depth)),
            "ctrl_stream": In(stream.Signature(self.Command)),
        })


class ImemMemory(ImemInterface):
    """
    Provides an ImemInterface to a Memory.

    The Memory must not be placed in the hierarchy by the user; ImemMemory will
    do so.
    """

    memory: Memory

    def __init__(self, *, memory):
        super().__init__(depth=memory.depth)
        self.memory = memory

    def elaborate(self, platform):
        m = Module()

        m.submodules.memory = memory = self.memory

        rp = memory.read_port()
        m.d.comb += rp.addr.eq(self.pc)
        m.d.comb += self.insn_stream.p.eq(rp.data)

        m.d.sync += self.insn_stream.valid.eq(1)

        with m.If(self.insn_stream.valid & self.insn_stream.ready):
            m.d.sync += self.pc.eq(self.pc + 1)
            m.d.sync += self.insn_stream.valid.eq(0)

        m.d.comb += self.ctrl_stream.ready.eq(1)
        with m.If(self.ctrl_stream.valid):
            m.d.sync += self.pc.eq(self.ctrl_stream.p.pc)
            m.d.sync += self.insn_stream.valid.eq(0)

        return m
