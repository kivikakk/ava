import random
from functools import partial

import pytest
from amaranth.hdl import Fragment
from amaranth.sim import Simulator
from amaranth.utils import bits_for

from avacore.rtl.divider import Divider, StreamingDivider
from tests import TestPlatform


def _test_divides(*, a, d, q=None, r=None, z=None, rapow, pipelined):
    # TODO: actually check pipelined use.
    dut = Divider(abits=bits_for(a), dbits=bits_for(d),
                  rapow=rapow, pipelined=pipelined)

    finished = False
    async def testbench(ctx):
        for _ in range(5):
            await ctx.tick()

        ctx.set(dut.a, a)
        ctx.set(dut.d, d)
        ctx.set(dut.start, 1)
        await ctx.tick()

        # Reset inputs to ensure it's not depending on them hanging around.
        ctx.set(dut.a, 0)
        ctx.set(dut.d, 0)
        ctx.set(dut.start, 0)

        steps = (bits_for(a) + rapow - 1) // rapow
        for i in range(steps):
            assert not ctx.get(dut.ready)
            await ctx.tick()

        assert ctx.get(dut.ready)

        if z:
            assert ctx.get(dut.z)
        else:
            assert [
                ctx.get(dut.q.as_signed()),
                ctx.get(dut.r),
                ctx.get(dut.z),
            ] == [q, r, 0]

        for _ in range(3):
            await ctx.tick()
            assert ctx.get(dut.ready) ^ pipelined

        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_testbench(testbench)
    sim.run_until(1)
    assert finished


@pytest.mark.parametrize("pipelined", [False, True])
@pytest.mark.parametrize("rapow", [1, 2, 3])
@pytest.mark.slow
def test_divider(rapow, pipelined):
    f = partial(_test_divides, rapow=rapow, pipelined=pipelined)
    f(a=7, d=3, q=2, r=1)
    f(a=100, d=4, q=25, r=0)
    f(a=779, d=8, q=97, r=3)
    f(a=779, d=0, z=1)


@pytest.mark.parametrize("pipelined", [False, True])
@pytest.mark.parametrize("rapow", [1, 2, 3])
@pytest.mark.slow
def test_divider_rand(rapow, pipelined):
    f = partial(_test_divides, rapow=rapow, pipelined=pipelined)
    for _ in range(10):
        a = random.randint(0, 1000000)
        d = random.randint(1, 1000000)
        f(a=a, d=d, q=a // d, r=a % d)


def _test_streaming_divides(*, a, d, q=None, r=None, z=None, rapow, pipelined):
    abits = bits_for(a, require_sign_bit=True)
    dbits = bits_for(d, require_sign_bit=True)

    dut = StreamingDivider(abits=abits, dbits=dbits, sign=True,
                           rapow=rapow, pipelined=pipelined)

    finished = False
    async def testbench(ctx):
        for _ in range(2):
            assert ctx.get(dut.w_stream.ready)

            ctx.set(dut.w_stream.p.a, a)
            ctx.set(dut.w_stream.p.d, d)
            ctx.set(dut.w_stream.valid, 1)
            await ctx.tick()
            ctx.set(dut.w_stream.valid, 0)

            assert not ctx.get(dut.w_stream.ready)

            steps = (abits + rapow - 1) // rapow
            for i in range(steps + 1):
                assert not ctx.get(dut.r_stream.valid)
                await ctx.tick()

            assert not ctx.get(dut.w_stream.ready)
            assert ctx.get(dut.r_stream.valid)

            if z:
                assert ctx.get(dut.r_stream.p.z)
            else:
                assert [
                    ctx.get(dut.r_stream.p.q),
                    ctx.get(dut.r_stream.p.r),
                    ctx.get(dut.r_stream.p.z),
                ] == [q, r, 0]

            ctx.set(dut.r_stream.ready, 1)
            await ctx.tick()
            ctx.set(dut.r_stream.ready, 0)
            assert ctx.get(dut.w_stream.ready)

        nonlocal finished
        finished = True

    sim = Simulator(Fragment.get(dut, TestPlatform()))
    sim.add_clock(1e-4)
    sim.add_testbench(testbench)
    sim.run_until(1)
    assert finished


@pytest.mark.parametrize("pipelined", [False, True])
@pytest.mark.parametrize("rapow", [1, 2, 3])
def test_streaming_divider(rapow, pipelined):
    # TODO: implement and test a pipelined use of this.
    # NOTE: I'm unsure if QBASIC's REM and MOD act exactly this way. We'll see.
    f = partial(_test_streaming_divides, rapow=rapow, pipelined=pipelined)
    f(a=779, d=8, q=97, r=3)
    f(a=779, d=-8, q=-97, r=3) # d<0
    f(a=-779, d=8, q=-98, r=5) # a<0
    f(a=-779, d=-8, q=98, r=5) # d<0, a<0
