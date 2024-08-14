from amaranth.hdl import Fragment
from amaranth.lib.memory import Memory
from amaranth.sim import Simulator

from avacore.rtl.imem import ImemMemory
from tests import TestPlatform


def test_imem():
    memory = Memory(shape=8, depth=1024, init=range(1023, -1, -1))
    dut = ImemMemory(memory=memory)

    finished = False
    async def testbench(ctx):
        assert not ctx.get(dut.insn_stream.valid)

        await ctx.tick()
        assert ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.insn_stream.p) == 255
        assert ctx.get(dut.pc) == 0

        ctx.set(dut.insn_stream.ready, 1)
        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)

        await ctx.tick()
        assert ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.insn_stream.p) == 254
        assert ctx.get(dut.pc) == 1

        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)

        await ctx.tick()
        assert ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.insn_stream.p) == 253
        assert ctx.get(dut.pc) == 2

        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)

        ctx.set(dut.insn_stream.ready, 0)
        for _ in range(2):
            await ctx.tick()
            assert ctx.get(dut.insn_stream.valid)
            assert ctx.get(dut.insn_stream.p) == 252
            assert ctx.get(dut.pc) == 3

        ctx.set(dut.insn_stream.ready, 1)
        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.ctrl_stream.ready)

        ctx.set(dut.ctrl_stream.p.pc, 256)
        ctx.set(dut.ctrl_stream.valid, 1)
        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)

        ctx.set(dut.ctrl_stream.valid, 0)
        await ctx.tick()
        assert ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.insn_stream.p) == 255
        assert ctx.get(dut.pc) == 256

        await ctx.tick()
        assert not ctx.get(dut.insn_stream.valid)

        await ctx.tick()
        assert ctx.get(dut.insn_stream.valid)
        assert ctx.get(dut.insn_stream.p) == 254
        assert ctx.get(dut.pc) == 257

        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_testbench(testbench)
    sim.run_until(1)
    assert finished
