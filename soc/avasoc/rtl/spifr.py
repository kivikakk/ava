import math

from amaranth import *
from amaranth.lib import data, stream, wiring
from amaranth.lib.wiring import In, Out

from ..targets import icebreaker


__all__ = ["SPIFlashReader"]


class SPIFlashReader(wiring.Component):
    Signature = wiring.Signature({
        "req": Out(stream.Signature(data.StructLayout({ "addr": 24, "len": 16 }))),
        "res": In(stream.Signature(8, always_ready=True)),
    })

    def __init__(self):
        super().__init__(SPIFlashReader.Signature)

    def elaborate(self, platform):
        m = Module()

        copi = Signal()
        cipo = Signal()
        cs = Signal()
        clk = Signal()

        match platform:
            case icebreaker():
                spi = platform.request("spi_flash_1x")
                m.d.comb += [
                    spi.copi.o.eq(copi),
                    cipo.eq(spi.cipo.i),
                    spi.cs.o.eq(cs),
                    spi.clk.o.eq(clk),
                ]

            case _:
                self.copi = Signal()
                self.cipo = Signal()
                self.cs = Signal()
                self.clk = Signal()
                m.d.comb += [
                    self.copi.eq(copi),
                    cipo.eq(self.cipo),
                    self.cs.eq(cs),
                    self.clk.eq(clk),
                ]

        freq = platform.default_clk_frequency
        # tRES1 (/CS High to Standby Mode without ID Read) and tDP (/CS High to
        # Power-down Mode) are both max 3us.
        TRES1_TDP_CYCLES = math.floor(freq / 1_000_000 * 3) + 1

        sr = Signal(32)
        snd_bitcount = Signal(range(max(32, TRES1_TDP_CYCLES)))

        rcv_bitcount = Signal(range(8))
        rcv_bytecount = Signal.like(self.req.p.len)

        addr = Signal(24)

        m.d.comb += [
            copi.eq(sr[-1]),
            clk.eq(cs & ~ClockSignal()),
            self.res.p.eq(sr[:8]),
        ]

        m.d.sync += self.res.valid.eq(0)

        with m.FSM():
            with m.State('idle'):
                m.d.comb += self.req.ready.eq(1)
                with m.If(self.req.valid):
                    m.d.sync += [
                        cs.eq(1),
                        sr.eq(0xAB00_0000),
                        snd_bitcount.eq(31),
                        addr.eq(self.req.p.addr),
                        rcv_bytecount.eq(self.req.p.len - 1),
                    ]
                    m.next = 'powerdown.release'

            with m.State('powerdown.release'):
                m.d.sync += [
                    snd_bitcount.eq(snd_bitcount - 1),
                    sr.eq(Cat(C(0b1, 1), sr[:-1])),
                ]
                with m.If(snd_bitcount == 0):
                    m.d.sync += [
                        cs.eq(0),
                        snd_bitcount.eq(TRES1_TDP_CYCLES - 1),
                    ]
                    m.next = 'wait'

            with m.State('wait'):
                with m.If(snd_bitcount != 0):
                    m.d.sync += snd_bitcount.eq(snd_bitcount - 1)
                with m.Else():
                    m.d.sync += [
                        cs.eq(1),
                        sr.eq(Cat(addr, C(0x03, 8))),
                        snd_bitcount.eq(31),
                        rcv_bitcount.eq(7),
                    ]
                    m.next = 'cmd'

            with m.State('cmd.wait'):
                m.d.comb += self.req.ready.eq(1)
                with m.If(self.req.valid):
                    m.d.sync += [
                        cs.eq(1),
                        sr.eq(Cat(self.req.p.addr, C(0x03, 8))),
                        snd_bitcount.eq(31),
                        rcv_bitcount.eq(7),
                        rcv_bytecount.eq(self.req.p.len - 1),
                    ]
                    m.next = 'cmd'

            with m.State('cmd'):
                m.d.sync += [
                    snd_bitcount.eq(snd_bitcount - 1),
                    sr.eq(Cat(C(0b1, 1), sr[:-1])),
                ]
                with m.If(snd_bitcount == 0):
                    m.next = 'recv'

            with m.State('recv'):
                m.d.sync += [
                    rcv_bitcount.eq(rcv_bitcount - 1),
                    sr.eq(Cat(cipo, sr[:-1])),
                ]
                with m.If(rcv_bitcount == 0):
                    m.d.sync += [
                        rcv_bytecount.eq(rcv_bytecount - 1),
                        rcv_bitcount.eq(7),
                        self.res.valid.eq(1),
                    ]
                    with m.If(rcv_bytecount == 0):
                        m.d.sync += cs.eq(0)
                        m.next = 'cmd.wait'

        return m
