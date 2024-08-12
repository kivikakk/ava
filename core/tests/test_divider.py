import random

import pytest
from amaranth.hdl import Fragment
from amaranth.sim import Simulator
from amaranth.utils import bits_for

from avacore.rtl.divider import Divider, StreamingDivider
from tests import TestPlatform


def _test_divides_one(*, a, d, q, r, z, rapow, pipelined):
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
        ctx.set(dut.start, 0)

        steps = (bits_for(a) + rapow - 1) // rapow + int(pipelined)
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


def _test_divides(*, a, d, q=None, r=None, z=None):
    for rapow in (1, 2, 3):
        for pipelined in (False, True):
            _test_divides_one(a=a, d=d, q=q, r=r, z=z,
                              rapow=rapow, pipelined=pipelined)


@pytest.mark.slow
def test_divider():
    _test_divides(a=7, d=3, q=2, r=1)
    _test_divides(a=100, d=4, q=25, r=0)
    _test_divides(a=779, d=8, q=97, r=3)
    _test_divides(a=779, d=0, z=1)

@pytest.mark.slow
def test_divider_rand():
    for _ in range(10):
        a = random.randint(0, 1000000)
        d = random.randint(1, 1000000)
        _test_divides(a=a, d=d, q=a // d, r=a % d)


def _test_streaming_divides_one(*, a, d, q, r, z, rapow):
    pipelined = False

    abits = bits_for(a, require_sign_bit=True)
    dbits = bits_for(d, require_sign_bit=True)

    dut = StreamingDivider(abits=abits, dbits=dbits, sign=True,
                           rapow=rapow)

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

            steps = (abits + rapow - 1) // rapow + int(pipelined)
            for i in range(steps + 2):
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


def _test_streaming_divides(*, a, d, q=None, r=None, z=None):
    # TODO: implement and test a pipelined use of this.
    for rapow in (1, 2, 3):
        _test_streaming_divides_one(a=a, d=d, q=q, r=r, z=z, rapow=rapow)


def test_streaming_divider():
    _test_streaming_divides(a=779, d=8, q=97, r=3)
    _test_streaming_divides(a=779, d=-8, q=-97, r=3) # d<0
    _test_streaming_divides(a=-779, d=8, q=-98, r=5) # a<0
    _test_streaming_divides(a=-779, d=-8, q=98, r=5) # d<0, a<0
    # NOTE: I'm unsure if QBASIC's REM and MOD act exactly this way. We'll see.
