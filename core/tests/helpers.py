import inspect
import subprocess
from pathlib import Path

from amaranth import *
from amaranth.sim import Simulator

from avacore.rtl.core import Core


__all__ = ["TestPlatform", "functional_test"]


class TestPlatform:
    simulation = True
    default_clk_frequency = 1e4


def compiled(filename, basic):
    baspath = Path(__file__).parent / f".{filename}.bas"
    avcpath = Path(__file__).parent / filename
    if baspath.exists():
        if baspath.read_text() == basic:
            if avcpath.exists():
                return avcpath.read_bytes()

    compiled = subprocess.check_output(
        ["avabasic", "compile", "-"],
        input=basic.encode('utf-8'))

    avcpath.write_bytes(compiled)
    baspath.write_text(basic)

    return compiled


def avabasic_run_output(filename):
    # XXX: needs to run after compiled(...).
    path = Path(__file__).parent / filename
    return subprocess.check_output(["avabasic", "run", path])


def functional_test(basic, *, output=None, stacks=None):
    # test_core.py's test_pc should produce "test_core_pc.avc".
    frame = inspect.stack()[1]
    assert frame.function[:5] == "test_"
    filename = f"{Path(frame.filename).stem}_{frame.function[5:]}.avc"

    code = compiled(filename, basic)

    if output is not None:
        assert avabasic_run_output(filename) == output

    dut = Core(code=code)
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


