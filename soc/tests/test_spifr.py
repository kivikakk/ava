from enum import Enum
import pytest
from amaranth import *
from amaranth.sim import Simulator

from avasoc.rtl.spifr import SPIFlashReader
from avasoc.targets import test

class SPIState(Enum):
    Powerdown = 1
    Command = 2
    Data = 3

def test_simple():
    dut = SPIFlashReader()

    DATA = {
        0x24_0000: [0xAB, 0x00, 0x77, 0xFF, 0x10],
        0x00_FFFF: [0x01, 0x23, 0x45, 0x67, 0x89],
    }

    async def spi(ctx):
        state = SPIState.Powerdown
        cmd = 0
        cmd_left = 32

        reading = None
        bit = 0

        last = None
        async for spiclk, cs, copi in ctx.changed(dut.clk).sample(dut.cs, dut.copi):
            if spiclk:
                assert cs
                cmd = (cmd << 1) | copi
                cmd_left -= 1
                if cmd_left == 0:
                    cmd_left = 32
                    match state:
                        case SPIState.Powerdown:
                            # TODO: ensure powerup time is held.
                            assert cmd == 0xAB00_0000
                            state = SPIState.Command
                            cmd = 0
                        case SPIState.Command:
                            assert (cmd >> 24) == 0x03
                            addr = cmd & 0x00FF_FFFF
                            reading = DATA.get(addr, [])
                            bit = 7
                            state = SPIState.Data

            if state == SPIState.Data:
                if not cs:
                    state = SPIState.Command
                    cmd = 0
                    cmd_left = 32
                elif not spiclk:
                    if reading:
                        ctx.set(dut.cipo, (reading[0] >> bit) & 1)
                        bit -= 1
                        if bit < 0:
                            reading.pop(0)
                            bit = 7
                    else:
                        ctx.set(dut.cipo, 1)

    async def bench(ctx):
        assert ctx.get(dut.req.ready)

        for addr in DATA.keys():
            expected = DATA[addr] + [0xFF, 0xFF]

            ctx.set(dut.req.p.addr, addr)
            ctx.set(dut.req.p.len, len(expected))
            ctx.set(dut.req.valid, 1)
            await ctx.tick()
            ctx.set(dut.req.p.addr, 0)
            ctx.set(dut.req.valid, 0)
            assert not ctx.get(dut.req.ready)

            for byte in expected:
                (actual,) = await ctx.tick().sample(dut.res.p).until(dut.res.valid)
                assert byte == actual

            await ctx.tick().until(dut.req.ready)

    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1e-6)
    sim.add_testbench(bench)
    sim.add_process(spi)
    sim.run()
