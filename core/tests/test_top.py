from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl import Core


class test:
    simulation = True
    default_clk_frequency = 8.0


def test_echo():
    dut = Core()

    async def testbench(ctx):
        # ctx.set(dut.uart.wr.ready, 1)
        # await ctx.tick().until(dut.uart.wr.valid)
        # assert ctx.get(dut.uart.wr.valid) == 1
        # assert ctx.get(dut.uart.wr.payload) == 0x33
        print()

        (v,) = await ctx.tick().sample(dut.stack.r_data).until(dut.stack.r_rdy)
        assert v == 1
        ctx.set(dut.stack.r_en, 1)
        await ctx.tick()
        ctx.set(dut.stack.r_en, 0)
        (v,) = await ctx.tick().sample(dut.stack.r_data).until(dut.stack.r_rdy)
        assert v == 2
        ctx.set(dut.stack.r_en, 1)
        await ctx.tick()
        ctx.set(dut.stack.r_en, 0)
        await ctx.tick().until(dut.done)


    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.run()
