from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform, compiled


def test_248():
    dut = Core(code=compiled('248.avc', """
        a% = 2
        b% = 4
        c% = a% * b%
        PRINT c%
    """))

    printed = bytearray()

    async def uart(ctx):
        async for clk_edge, rst_value, wr_valid, wr_p in ctx.tick().sample(dut.uart.wr.valid, dut.uart.wr.p):
            if rst_value:
                pass
            elif clk_edge and wr_valid:
                printed.append(wr_p)

    async def testbench(ctx):
        await ctx.tick().until(dut.done)
        assert printed == b'8\n'

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1 / 8)
    sim.add_process(uart)
    sim.add_testbench(testbench)
    sim.run()
