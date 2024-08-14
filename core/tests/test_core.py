from amaranth import *
from amaranth.sim import Simulator

from avacore.rtl.core import Core
from tests import TestPlatform, compiled, avabasic_run_output


def _test(filename, basic, *, output=None, stacks=None):
    dut = Core(code=compiled(filename, basic))

    printed = bytearray()

    async def uart(ctx):
        ctx.set(dut.uart.wr.ready, 1)
        async for clk_edge, rst_value, wr_valid, wr_p in \
                ctx.tick().sample(dut.uart.wr.valid, dut.uart.wr.p):
            if wr_valid:
                printed.append(wr_p)

    async def stack_monitor(ctx):
        ws = dut.stack.w_stream
        rs = dut.stack.r_stream
        stack = []
        i = 0

        async for clk_edge, rst_value, w_valid, w_ready, w_p, r_valid, r_ready, r_p in \
                ctx.tick().sample(ws.valid, ws.ready, ws.p,
                                  rs.valid, rs.ready, rs.p):
            if w_valid and w_ready:
                stack.append(w_p)
                assert stacks.pop(0) == stack, f"stacks index {i} mismatch on write"
                assert not (r_valid and r_ready)
                i += 1
            if r_valid and r_ready:
                stack.pop()
                assert stacks.pop(0) == stack, f"stacks index {i} mismatch on read"
                assert not (w_valid and w_ready)
                i += 1

    finished = False
    async def testbench(ctx):
        await ctx.tick().until(dut.done)
        assert ctx.get(dut.stack.level) == 0, "stack should be empty after running"
        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_process(uart)
    if stacks is not None:
        sim.add_process(stack_monitor)
    sim.add_testbench(testbench)
    sim.run_until(1)
    assert finished
    
    if output is not None:
        assert printed == output
        assert avabasic_run_output(filename) == output


def test_68():
    _test('68.avc', """
        a% = 2
        b% = 34
        c% = a% * b%
        PRINT c%
    """, output=b' 68 \n', stacks=[
        [2],
        [],
        [34],
        [],
        [2],
        [2, 34],
        [2],
        [],
        [68],
        [],
        [68],
        [],
    ])


def test_680():
    _test('680.avc', """
        PRINT (2 * 34) * 10
    """, output=b' 680 \n', stacks=[
        [2],
        [2, 34],
        [2],
        [],
        [68],
        [68, 10],
        [68],
        [],
        [680],
        [],
    ])
