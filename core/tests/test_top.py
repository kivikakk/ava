from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl import Core


class test:
    simulation = True
    default_clk_frequency = 8.0


def test_echo():
    dut = Core()

    async def testbench(ctx):
        ctx.set(dut.uart.rd.payload, 0x7a)
        ctx.set(dut.uart.rd.valid, 1)
        await ctx.tick()
        assert ctx.get(dut.uart.wr.payload) == 0x7a
        assert ctx.get(dut.uart.wr.valid) == 1

    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.run()
