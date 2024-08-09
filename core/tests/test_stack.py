from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.stack import Stack


class test:
    simulation = True
    default_clk_frequency = 8.0


def test_stack():
    dut = Stack(width=8, depth=2)

    def assertStack(ctx, *, rv, rp=None, wr):
        assert ctx.get(dut.r_stream.valid) == rv
        if rp is not None:
            assert ctx.get(dut.r_stream.payload) == rp
        assert ctx.get(dut.w_stream.ready) == wr

    async def testbench(ctx):
        assertStack(ctx, rv=0, wr=1)

        # read on empty

        ctx.set(dut.r_stream.ready, 1)

        await ctx.tick()

        ctx.set(dut.r_stream.ready, 0)
        assertStack(ctx, rv=0, wr=1)

        # write value

        ctx.set(dut.w_stream.payload, 0x84)  # BA

        await ctx.tick()

        assertStack(ctx, rv=0, wr=1)
        ctx.set(dut.w_stream.valid, 1)

        await ctx.tick()

        ctx.set(dut.w_stream.valid, 0)

        for i in range(1):
            assertStack(ctx, rv=0, wr=1)
            await ctx.tick()

        assertStack(ctx, rv=1, rp=0x84, wr=1)

        # write second value, make sure it's on top

        ctx.set(dut.w_stream.payload, 0x14)  # KA

        await ctx.tick()

        assertStack(ctx, rv=1, wr=1)
        ctx.set(dut.w_stream.valid, 1)

        await ctx.tick()

        ctx.set(dut.w_stream.valid, 0)

        for i in range(1):
            assertStack(ctx, rv=0, wr=0)
            await ctx.tick()

        assertStack(ctx, rv=1, rp=0x14, wr=0)

        # pop top value

        ctx.set(dut.r_stream.ready, 1)

        await ctx.tick()

        ctx.set(dut.r_stream.ready, 0)

        for i in range(1):
            assertStack(ctx, rv=0, wr=1)
            await ctx.tick()

        assertStack(ctx, rv=1, rp=0x84, wr=1)

        # pop last value

        ctx.set(dut.r_stream.ready, 1)

        await ctx.tick()

        ctx.set(dut.r_stream.ready, 0)

        for i in range(2):
            assertStack(ctx, rv=0, wr=1)
            await ctx.tick()

        assertStack(ctx, rv=0, wr=1)

    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1 / 8)
    sim.add_testbench(testbench)
    sim.run()
