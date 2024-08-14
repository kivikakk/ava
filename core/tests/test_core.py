from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform, compiled, avabasic_run_output


def _test_output(filename, basic, expected):
    dut = Core(code=compiled(filename, basic))

    printed = bytearray()

    async def uart(ctx):
        ctx.set(dut.uart.wr.ready, 1)
        async for clk_edge, rst_value, wr_valid, wr_p in \
                ctx.tick().sample(dut.uart.wr.valid, dut.uart.wr.p):
            if wr_valid:
                printed.append(wr_p)

    finished = False
    async def testbench(ctx):
        await ctx.tick().until(dut.done)
        assert ctx.get(dut.stack.level) == 0, "stack should be empty after running"
        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_process(uart)
    sim.add_testbench(testbench)
    sim.run_until(1)

    assert printed == expected
    assert finished
    assert avabasic_run_output(filename) == expected


def test_248():
    _test_output('68.avc', """
        a% = 2
        b% = 34
        c% = a% * b%
        PRINT c%
    """, b' 68 \n')

    _test_output('680.avc', """
        PRINT (2 * 34) * 10
    """, b' 680 \n')
