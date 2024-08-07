from amaranth.hdl import Fragment
from amaranth.sim import Simulator
from avacore.rtl import Blinker


class test:
    simulation = True
    default_clk_frequency = 8.0


def test_blinks():
    dut = Blinker()

    async def testbench(ctx):
        for ledr in [0, 1, 1, 0, 0, 1, 1, 0]:
            for _ in range(2):
                assert ctx.get(dut.ledr) == ledr
                assert ctx.get(dut.ledg)
                await ctx.tick()

    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.run()
