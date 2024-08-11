from amaranth.hdl import Fragment
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform, compiled, avabasic_run_output


def _test_output(filename, basic, output):
    dut = Core(code=compiled(filename, basic))

    printed = bytearray()

    async def uart(ctx):
        async for clk_edge, rst_value, wr_valid, wr_p in ctx.tick().sample(dut.uart.wr.valid, dut.uart.wr.p):
            if rst_value:
                pass
            elif clk_edge and wr_valid:
                printed.append(wr_p)

    finished = False
    async def testbench(ctx):
        await ctx.tick().until(dut.done)
        assert printed == output
        assert ctx.get(dut.stack.level) == 0, "stack should be empty after running"
        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_process(uart)
    sim.add_testbench(testbench)
    sim.run_until(1)

    assert finished
    assert avabasic_run_output(filename) == output


def test_248():
    _test_output('248.avc', """
        a% = 2
        b% = 4
        c% = a% * b%
        PRINT c%
    """, b'8\n')
