from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import Out

from .imem import IMem
from .spifr import SPIFlashReader
from .uart import UART


__all__ = ["Core"]

class Core(wiring.Component):
    # IMEM is backed by SPI flash; we use VexRiscv's built-in I$.
    SPI_IMEM_BASE = 0x0080_0000

    # We're targetting the iCE40UP SPRAM for DMEM, which gives us 128KiB.
    # SPRAM is in 4x 32KiB blocks (16 bits wide, 16,384 deep).
    # SPRAM isn't initialisable[^1]; we init it from BRAM.  DMEM is still small
    # enough that this is feasible.
    #
    # BSS and minimum stack size availability are asserted in the linker script.
    #
    # [^1]: requiring an Amaranth hack to let us use the existing Memory stuff;
    #      if we want to unhack it slightly, we can replace it with Instances
    #      that produce the right $memrd_v2/$memwr_v2s, and wire up the ports.
    DMEM_BYTES = 128 * 1024

    DMEM_BASE = 0x4000_0000
    UART_BASE = 0x8000_0000
    CSR_EXIT  = 0x8000_ffff

    running: Out(1)

    spifr_bus: Out(SPIFlashReader.Signature)

    def __init__(self, *, dmem):
        super().__init__()
        self._dmem = dmem

    def elaborate(self, platform):
        m = Module()

        running = Signal(init=1)
        m.d.comb += self.running.eq(running)

        i_timerInterrupt = Signal()
        i_externalInterrupt = Signal()
        i_softwareInterrupt = Signal()
        i_reset = Signal(init=1)

        m.d.sync += i_reset.eq(0)

        m.submodules.uart = uart = UART(
            self._uart, baud=115_200, tx_fifo_depth=32, rx_fifo_depth=32)

        # TODO: redo IMEM with Wishbone. Note that IBusCachedPlugin's Wishbone
        # bridge (i.e. InstructionCacheMemBus.toWishbone) uses incrementing
        # # burst read, which dovetails well with the SPI flash protocol, but
        # requires a rework of the interleaving bits and pieces.
        m.submodules.imem = imem = IMem(base=self.SPI_IMEM_BASE)
        wiring.connect(m, wiring.flipped(self.spifr_bus), imem.spifr_bus)

        o_dBusWishbone_CYC = Signal()
        o_dBusWishbone_STB = Signal()
        i_dBusWishbone_ACK = Signal()
        o_dBusWishbone_WE = Signal()
        o_dBusWishbone_ADR = Signal(30)
        i_dBusWishbone_DAT_MISO = Signal(32)
        o_dBusWishbone_DAT_MOSI = Signal(32)
        o_dBusWishbone_SEL = Signal(4)
        i_dBusWishbone_ERR = Signal()

        m.submodules.dmem_init = dmem_init = Memory(shape=32, depth=len(self._dmem), init=self._dmem)
        dmem_init_rp = dmem_init.read_port()

        m.submodules.dmem = dmem = Memory(shape=32, depth=self.DMEM_BYTES // 4, init=None)
        dmem_wp = dmem.write_port(granularity=8)
        dmem_rp = dmem.read_port(transparent_for=[dmem_wp])

        wr = Signal()
        mask = Signal(4)
        address = Signal(32)
        data = Signal(32)

        dmem_addr = Signal.like(dmem_wp.addr)
        m.d.comb += [
            dmem_addr.eq(address >> 2),
            dmem_wp.addr.eq(dmem_addr),
            dmem_rp.addr.eq(dmem_addr),
        ]

        unhandled_dbus = lambda: Print(Format(
            "unhandled dBus {} at {:08x} mask {:04b} (data {:08x})",
            wr, address, mask, data,
        ))

        with m.FSM():
            with m.State('init.wait'):
                m.next = 'init.write'

            with m.State('init.write'):
                m.d.comb += [
                    dmem_addr.eq(dmem_init_rp.addr),
                    dmem_wp.data.eq(dmem_init_rp.data),
                    dmem_wp.en.eq(0b1111),
                    dmem_rp.en.eq(0),
                ]
                with m.If(dmem_init_rp.addr == len(self._dmem) - 1):
                    m.d.sync += address.eq((dmem_init_rp.addr << 2) + 4)
                    m.next = 'zero'
                with m.Else():
                    m.d.sync += dmem_init_rp.addr.eq(dmem_init_rp.addr + 1)
                    m.next = 'init.wait'

            with m.State('zero'):
                m.d.comb += [
                    dmem_wp.data.eq(0),
                    dmem_wp.en.eq(0b1111),
                    dmem_rp.en.eq(0),
                ]
                with m.If(address == self.DMEM_BYTES - 4):
                    m.next = 'ready'
                with m.Else():
                    m.d.sync += address.eq(address + 4)

            with m.State('ready'):
                # TODO: is the Wishbone controller allowed to change data after
                # asserting CYC/STB? if not, we can gain a cycle.
                with m.If(o_dBusWishbone_CYC & o_dBusWishbone_STB):
                    m.d.sync += [
                        wr.eq(o_dBusWishbone_WE),
                        mask.eq(o_dBusWishbone_SEL),
                        address.eq(o_dBusWishbone_ADR << 2),
                        data.eq(o_dBusWishbone_DAT_MOSI),
                    ]
                    m.next = 'consider'

            with m.State('consider'):
                assert (self.DMEM_BASE & 0x00FF_FFFF) == 0
                with m.If(address[24:] == (self.DMEM_BASE >> 24)):
                    with m.If(wr):
                        # m.d.sync += Print(Format(
                        #     "[d WR @ {:06x} #{:04b} = {:08x}]",
                        #     dmem_addr, mask, data,
                        # ))
                        m.d.comb += [
                            dmem_wp.data.eq(data),
                            dmem_wp.en.eq(mask),
                            dmem_rp.en.eq(0),
                        ]
                        m.d.comb += i_dBusWishbone_ACK.eq(1)
                        m.next = 'ready'
                    with m.Else():
                        m.next = 'read'
                with m.Elif((address == self.UART_BASE) & (mask == 0b0001)):
                    m.d.comb += i_dBusWishbone_ACK.eq(1)
                    m.next = 'ready'
                    with m.If(wr):
                        m.d.comb += uart.wr.p.eq(data[:8])
                        m.d.comb += uart.wr.valid.eq(1)
                        with m.If(~uart.wr.ready):
                            m.d.comb += i_dBusWishbone_ACK.eq(0)
                            m.next = 'uart.write.stall'
                    with m.Else():
                        m.d.comb += uart.rd.ready.eq(1)
                        m.d.comb += i_dBusWishbone_DAT_MISO.eq(Mux(uart.rd.valid, uart.rd.p, 0))
                with m.Elif((address == self.UART_BASE) & (mask == 0b0011) & ~wr):
                    m.d.comb += uart.rd.ready.eq(1)
                    m.d.comb += i_dBusWishbone_DAT_MISO.eq(Cat(uart.rd.p, uart.rd.valid))
                    m.d.comb += i_dBusWishbone_ACK.eq(1)
                    m.next = 'ready'
                with m.Elif((address == self.CSR_EXIT) & (mask == 0b0001) & wr & data[0]):
                    m.d.sync += Print("\n! CSR_EXIT signalled -- stopped")
                    m.d.sync += running.eq(0)
                with m.Else():
                    m.d.sync += unhandled_dbus()
                    m.d.comb += i_dBusWishbone_ERR.eq(1)
                    m.next = 'ready'

            with m.State('uart.write.stall'):
                m.d.comb += uart.wr.p.eq(data[:8])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.d.comb += i_dBusWishbone_ACK.eq(1)
                    m.next = 'ready'

            with m.State('read'):
                # m.d.sync += Print(Format(
                #     "[d RD @ {:06x} #{:04b} = {:08x}]",
                #     dmem_addr, mask, dmem_rp.data,
                # ))
                m.next = 'ready'
                m.d.comb += i_dBusWishbone_ACK.eq(1)
                m.d.comb += i_dBusWishbone_DAT_MISO.eq(dmem_rp.data)

        m.submodules.vexriscv = Instance("VexRiscv",
            i_timerInterrupt=i_timerInterrupt,
            i_externalInterrupt=i_externalInterrupt,
            i_softwareInterrupt=i_softwareInterrupt,
            o_iBus_cmd_valid=imem.cmd.valid,
            i_iBus_cmd_ready=imem.cmd.ready,
            o_iBus_cmd_payload_address=imem.cmd.p.address,
            o_iBus_cmd_payload_size=imem.cmd.p.size,
            i_iBus_rsp_valid=imem.rsp.valid,
            i_iBus_rsp_payload_data=imem.rsp.p.data,
            i_iBus_rsp_payload_error=imem.rsp.p.error,
            o_dBusWishbone_CYC=o_dBusWishbone_CYC,
            o_dBusWishbone_STB=o_dBusWishbone_STB,
            i_dBusWishbone_ACK=i_dBusWishbone_ACK,
            o_dBusWishbone_WE=o_dBusWishbone_WE,
            o_dBusWishbone_ADR=o_dBusWishbone_ADR,
            i_dBusWishbone_DAT_MISO=i_dBusWishbone_DAT_MISO,
            o_dBusWishbone_DAT_MOSI=o_dBusWishbone_DAT_MOSI,
            o_dBusWishbone_SEL=o_dBusWishbone_SEL,
            i_dBusWishbone_ERR=i_dBusWishbone_ERR,
            i_clk=ClockSignal(),
            i_reset=i_reset,
        )

        return m
