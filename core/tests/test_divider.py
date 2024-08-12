import random

from amaranth.hdl import Fragment
from amaranth.sim import Simulator
from amaranth.utils import bits_for

from avacore.rtl.divider import Divider, StreamingDivider
from tests import TestPlatform


def _test_divides_one(*, a, d, q, r, z, rapow, pipelined):
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
                ctx.get(dut.q),
                ctx.get(dut.r),
                ctx.get(dut.z),
            ] == [q, r, z]

        # This behaviour is per the original VHDL, I think.
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


def _test_divides(*, a, d, q=None, r=None, z):
    for rapow in (1, 2, 3):
        for pipelined in (False, True):
            _test_divides_one(a=a, d=d, q=q, r=r, z=z,
                              rapow=rapow, pipelined=pipelined)


def test_divider():
    # TODO: test negative numbers
    _test_divides(a=7, d=3, q=2, r=1, z=0)
    _test_divides(a=100, d=4, q=25, r=0, z=0)
    _test_divides(a=779, d=8, q=97, r=3, z=0)
    _test_divides(a=779, d=0, z=1)
    for _ in range(10):
        a = random.randint(0, 1000000)
        d = random.randint(1, 1000000)
        _test_divides(a=a, d=d, q=a // d, r=a % d, z=0)


def test_streaming_divider():
    a, d, q, r, z = 779, 8, 97, 3, 0
    rapow = 3
    pipelined = True

    dut = StreamingDivider(abits=bits_for(a), dbits=bits_for(d),
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

            steps = (bits_for(a) + rapow - 1) // rapow + int(pipelined)
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
                ] == [q, r, z]

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
