from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform


def test_hello():
    dut = Core()

    printed = bytearray()

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
        await ctx.tick().until(dut.done)

        assert printed == b'3\n'

    async def uart(ctx):
        async for clk_edge, rst_value, wr_valid, wr_p in ctx.tick().sample(dut.uart.wr.valid, dut.uart.wr.p):
            if clk_edge and wr_valid:
                printed.append(wr_p)

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.add_process(uart)
    sim.run()
