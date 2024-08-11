from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.printer import Printer
from tests import TestPlatform


def _test_prints(input, expected):
    dut = Printer()

    finished = False
    async def testbench(ctx):
        ctx.set(dut.w_stream.p, input)
        ctx.set(dut.w_stream.valid, 1)

        await ctx.tick()

        ctx.set(dut.w_stream.valid, 0)

        output = bytearray()
        async for _, _, w_ready in ctx.tick().sample(dut.w_stream.ready):
            if w_ready:
                break
            ctx.set(dut.r_stream.ready, 0)
            if ctx.get(dut.r_stream.valid):
                output.append(ctx.get(dut.r_stream.p))
                ctx.set(dut.r_stream.ready, 1)

        assert output == expected
        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_testbench(testbench)
    sim.run_until(1)
    assert finished


def test_0():
    _test_prints(0, b' 0 ')

def test_9():
    _test_prints(9, b' 9 ')

def test_n7():
    _test_prints(-7, b'-7 ')

def test_10():
    _test_prints(10, b' 10 ')
