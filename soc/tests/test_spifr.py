import struct
from enum import Enum

from amaranth import *
from amaranth.lib import wiring
from amaranth.sim import Simulator

from avasoc.rtl.imem import WishboneIMem
from avasoc.rtl.spifr import SPIFlashReader
from avasoc.targets import test


class SPIState(Enum):
    Powerdown = 1
    Command = 2
    Data = 3


DATA = {
    0x24_0000: [0xAB, 0x00, 0x77, 0xFF, 0x10],
    0x00_FFFF: [0x01, 0x23, 0x45, 0x67, 0x89],
    0x88_8888: [],
    0x11_AAAA: [0xCC],
}

data_bytes = {}
for start, elems in DATA.items():
    for e in elems:
        data_bytes[start] = e
        start += 1


def spi_process(*, spifr):
    async def spi(ctx):
        state = SPIState.Powerdown
        cmd = 0
        cmd_left = 32

        reading = None
        addr = 0
        bit = 0

        async for spiclk, cs, copi in ctx.changed(spifr.clk).sample(spifr.cs, spifr.copi):
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
                            print(f"spi_process: read at {addr:06x}")
                            reading = data_bytes.get(addr, 0xFF)
                            bit = 7
                            state = SPIState.Data

            if state == SPIState.Data:
                if not cs:
                    state = SPIState.Command
                    cmd = 0
                    cmd_left = 32
                elif not spiclk:
                    ctx.set(spifr.cipo, (reading >> bit) & 1)
                    bit -= 1
                    if bit < 0:
                        addr += 1
                        reading = data_bytes.get(addr, 0xFF)
                        bit = 7
    return spi


def test_simple():
    dut = SPIFlashReader()

    async def bench(ctx):
        for addr in DATA.keys():
            expected = DATA[addr] + [0xFF, 0xFF]

            await ctx.tick().until(dut.addr_stb.ready)

            ctx.set(dut.addr_stb.p, addr)
            ctx.set(dut.addr_stb.valid, 1)

            await ctx.tick()

            ctx.set(dut.addr_stb.p, 0)
            ctx.set(dut.addr_stb.valid, 0)
            assert not ctx.get(dut.addr_stb.ready)

            for byte in expected:
                (actual,) = await ctx.tick().sample(dut.res.p).until(dut.res.valid)
                assert byte == actual

            ctx.set(dut.stop_stb.valid, 1)
            await ctx.tick().until(dut.stop_stb.ready)
            ctx.set(dut.stop_stb.valid, 0)

        await ctx.tick().until(dut.addr_stb.ready)

    sim = Simulator(Fragment.get(dut, test()))
    sim.add_clock(1e-6)
    sim.add_testbench(bench)
    sim.add_process(spi_process(spifr=dut))
    sim.run()


def test_wb():
    m = Module()

    m.submodules.imem = imem = WishboneIMem(base=0)

    m.submodules.spifr = spifr = SPIFlashReader()
    wiring.connect(m, wiring.flipped(spifr), imem.spifr_bus)

    async def bench(ctx):
        addr = 0x24_0000
        data = DATA[addr]
        while len(data) % 4 != 0:
            data = data + [0xFF]

        ctx.set(imem.wb_bus.cyc, 1)
        ctx.set(imem.wb_bus.stb, 1)
        ctx.set(imem.wb_bus.sel, 0b1111)

        while data:
            ctx.set(imem.wb_bus.adr, addr >> 2)
            (d,) = await ctx.tick().sample(imem.wb_bus.dat_r).until(imem.wb_bus.ack)
            assert d == struct.unpack('<L', bytes(data[:4]))[0]

            addr += 4
            data = data[4:]

        ctx.set(imem.wb_bus.cyc, 0)
        ctx.set(imem.wb_bus.stb, 0)

    sim = Simulator(Fragment.get(m, test()))
    sim.add_clock(1e-6)
    sim.add_testbench(bench)
    sim.add_process(spi_process(spifr=spifr))
    sim.run()
