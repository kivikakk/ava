import math

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import icebreaker


__all__ = ["SPIFlashReader", "SPIFlashReaderBus"]


SPIHardwareBus = wiring.Signature({
    "copi": Out(1),
    "cipo": In(1),
    "cs": Out(1),
    "clk": Out(1),
})


SPIFlashReaderBus = wiring.Signature({
    "addr": Out(24),
    "len": Out(16),
    "stb": Out(1),
    "busy": In(1),
    "data": In(8),
    "valid": In(1),
})


class SPIFlashReader(wiring.Component):
    spi: Out(SPIHardwareBus)
    bus: In(SPIFlashReaderBus)

    def __init__(self):
        super().__init__()

    def elaborate(self, platform):
        m = Module()

        if getattr(platform, "simulation", False):
            # Blackboxed in tests.
            return m

        match platform:
            case icebreaker():
                spi = platform.request("spi_flash_1x")
                m.d.comb += [
                    spi.copi.o.eq(self.spi.copi),
                    self.spi.cipo.eq(spi.cipo.i),
                    spi.cs.o.eq(self.spi.cs),
                    spi.clk.o.eq(self.spi.clk),
                ]

            case _:
                raise NotImplementedError

        freq = platform.default_clk_frequency
        # tRES1 (/CS High to Standby Mode without ID Read) and tDP (/CS High to
        # Power-down Mode) are both max 3us.
        TRES1_TDP_CYCLES = math.floor(freq / 1_000_000 * 3) + 1

        sr = Signal(32)
        snd_bitcount = Signal(range(max(32, TRES1_TDP_CYCLES)))

        rcv_bitcount = Signal(range(8))
        rcv_bytecount = Signal.like(self.bus.len)

        m.d.comb += [
            self.spi.copi.eq(sr[-1]),
            self.spi.clk.eq(self.spi.cs & ~ClockSignal()),
            self.bus.data.eq(sr[:8]),
        ]

        m.d.sync += self.bus.valid.eq(0)

        with m.FSM() as fsm:
            m.d.comb += self.bus.busy.eq(~fsm.ongoing('idle'))

            with m.State('idle'):
                with m.If(self.bus.stb):
                    m.d.sync += [
                        self.spi.cs.eq(1),
                        sr.eq(0xAB000000),
                        snd_bitcount.eq(31),
                    ]
                    m.next = 'powerdown.release'

            with m.State('powerdown.release'):
                m.d.sync += [
                    snd_bitcount.eq(snd_bitcount - 1),
                    sr.eq(Cat(C(0b1, 1), sr[:-1])),
                ]
                with m.If(snd_bitcount == 0):
                    m.d.sync += [
                        self.spi.cs.eq(0),
                        snd_bitcount.eq(TRES1_TDP_CYCLES - 1),
                    ]
                    m.next = 'wait'

            with m.State('wait'):
                with m.If(snd_bitcount != 0):
                    m.d.sync += snd_bitcount.eq(snd_bitcount - 1)
                with m.Else():
                    m.d.sync += [
                        self.spi.cs.eq(1),
                        sr.eq(Cat(self.bus.addr, C(0x03, 8))),
                        snd_bitcount.eq(31),
                        rcv_bitcount.eq(7),
                        rcv_bytecount.eq(self.bus.len - 1),
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
                    sr.eq(Cat(self.spi.cipo, sr[:-1])),
                ]
                with m.If(rcv_bitcount == 0):
                    m.d.sync += [
                        rcv_bytecount.eq(rcv_bytecount - 1),
                        rcv_bitcount.eq(7),
                        self.bus.valid.eq(1),
                    ]
                    with m.If(rcv_bytecount == 0):
                        m.d.sync += [
                            self.spi.cs.eq(0),
                            snd_bitcount.eq(TRES1_TDP_CYCLES - 1),
                        ]
                        m.next = 'powerdown'
                    with m.Else():
                        m.next = 'recv'

            with m.State('powerdown'):
                with m.If(snd_bitcount != 0):
                    m.d.sync += snd_bitcount.eq(snd_bitcount - 1)
                with m.Else():
                    m.next = 'idle'

        return m
