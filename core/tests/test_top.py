from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform


def test_echo():
    dut = Core()

    async def testbench(ctx):
        # ctx.set(dut.uart.wr.ready, 1)
        # await ctx.tick().until(dut.uart.wr.valid)
        # assert ctx.get(dut.uart.wr.valid) == 1
        # assert ctx.get(dut.uart.wr.payload) == 0x33
        print()

        # await ctx.tick().until(dut.done)

        (v,) = await ctx.tick().sample(dut.slots.data[0]).until(dut.slots.data[0] != 0)
        assert v == 1
        (v,) = await ctx.tick().sample(dut.slots.data[1]).until(dut.slots.data[1] != 0)
        assert v == 2
        # (v,) = await ctx.tick().sample(dut.slots.data[0]).until(dut.slots.data[0] != 1)
        # assert v == 3
        await ctx.tick().until(dut.done)


    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.run()
