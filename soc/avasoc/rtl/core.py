from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import Out

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
        o_iBus_cmd_valid = Signal()
        i_iBus_cmd_ready = Signal()
        o_iBus_cmd_payload_address = Signal(32)
        o_iBus_cmd_payload_size = Signal(3)
        i_iBus_rsp_valid = Signal()
        i_iBus_rsp_payload_data = Signal(32)
        i_iBus_rsp_payload_error = Signal()
        o_dBus_cmd_valid = Signal()
        i_dBus_cmd_ready = Signal()
        o_dBus_cmd_payload_wr = Signal()
        o_dBus_cmd_payload_mask = Signal(4)
        o_dBus_cmd_payload_address = Signal(32)
        o_dBus_cmd_payload_data = Signal(32)
        o_dBus_cmd_payload_size = Signal(2)
        i_dBus_rsp_ready = Signal()
        i_dBus_rsp_error = Signal()
        i_dBus_rsp_data = Signal(32)
        i_reset = Signal(init=1)

        m.d.sync += i_reset.eq(0)

        m.submodules.vexriscv = Instance("VexRiscv",
            i_timerInterrupt=i_timerInterrupt,
            i_externalInterrupt=i_externalInterrupt,
            i_softwareInterrupt=i_softwareInterrupt,
            o_iBus_cmd_valid=o_iBus_cmd_valid,
            i_iBus_cmd_ready=i_iBus_cmd_ready,
            o_iBus_cmd_payload_address=o_iBus_cmd_payload_address,
            o_iBus_cmd_payload_size=o_iBus_cmd_payload_size, # XXX
            i_iBus_rsp_valid=i_iBus_rsp_valid,
            i_iBus_rsp_payload_data=i_iBus_rsp_payload_data,
            i_iBus_rsp_payload_error=i_iBus_rsp_payload_error,
            o_dBus_cmd_valid=o_dBus_cmd_valid,
            i_dBus_cmd_ready=i_dBus_cmd_ready,
            o_dBus_cmd_payload_wr=o_dBus_cmd_payload_wr,
            o_dBus_cmd_payload_mask=o_dBus_cmd_payload_mask,
            o_dBus_cmd_payload_address=o_dBus_cmd_payload_address,
            o_dBus_cmd_payload_data=o_dBus_cmd_payload_data,
            o_dBus_cmd_payload_size=o_dBus_cmd_payload_size,
            i_dBus_rsp_ready=i_dBus_rsp_ready,
            i_dBus_rsp_error=i_dBus_rsp_error,
            i_dBus_rsp_data=i_dBus_rsp_data,
            i_clk=ClockSignal(),
            i_reset=i_reset,
        )

        m.submodules.uart = uart = UART(
            self._uart, baud=115_200, tx_fifo_depth=32, rx_fifo_depth=32)

        # TODO: use Wishbone for IMEM, DMEM.
        imem_ix = Signal(range(32))
        m.d.sync += self.spifr_bus.req.valid.eq(0)
        m.d.sync += i_iBus_rsp_valid.eq(0)

        with m.FSM():
            with m.State('init'):
                m.d.comb += i_iBus_cmd_ready.eq(self.spifr_bus.req.ready)
                with m.If(i_iBus_cmd_ready & o_iBus_cmd_valid):
                    m.d.sync += Assert(o_iBus_cmd_payload_size == 5)  # i.e. 2**5 == 32 bytes
                    m.d.sync += [
                        imem_ix.eq(0),
                        self.spifr_bus.req.p.addr.eq(self.SPI_IMEM_BASE + o_iBus_cmd_payload_address),
                        self.spifr_bus.req.p.len.eq(32),
                        self.spifr_bus.req.valid.eq(1),
                    ]
                    m.next = 'read.wait'

            with m.State('read.wait'):
                with m.If(self.spifr_bus.res.valid):
                    with m.Switch(imem_ix[:2]):
                        with m.Case(0):
                            m.d.sync += i_iBus_rsp_payload_data[:8].eq(self.spifr_bus.res.p)
                        with m.Case(1):
                            m.d.sync += i_iBus_rsp_payload_data[8:16].eq(self.spifr_bus.res.p)
                        with m.Case(2):
                            m.d.sync += i_iBus_rsp_payload_data[16:24].eq(self.spifr_bus.res.p)
                        with m.Case(3):
                            m.d.sync += i_iBus_rsp_payload_data[24:].eq(self.spifr_bus.res.p)
                            m.d.sync += i_iBus_rsp_valid.eq(1)
                    with m.If(imem_ix == 31):
                        m.next = 'init'
                    with m.Else():
                        m.d.sync += imem_ix.eq(imem_ix + 1)

        m.submodules.dmem_init = dmem_init = Memory(shape=32, depth=len(self._dmem), init=self._dmem)
        dmem_init_rp = dmem_init.read_port()

        m.submodules.dmem = dmem = Memory(shape=32, depth=self.DMEM_BYTES // 4, init=None)
        dmem_wp = dmem.write_port(granularity=8)
        dmem_rp = dmem.read_port(transparent_for=[dmem_wp])

        wr = Signal()
        mask = Signal(4)
        address = Signal(32)
        data = Signal(32)
        size = Signal(2)

        dmem_addr = Signal.like(dmem_wp.addr)
        m.d.comb += [
            dmem_addr.eq(address >> 2),
            dmem_wp.addr.eq(dmem_addr),
            dmem_rp.addr.eq(dmem_addr),
        ]

        unhandled_dbus = lambda: Print(Format(
            "unhandled dBus {} at {:08x} mask {:04b} size {} (data {:08x})",
            wr, address, mask, size, data,
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
                m.d.comb += i_dBus_cmd_ready.eq(1)
                with m.If(o_dBus_cmd_valid):
                    m.d.sync += [
                        wr.eq(o_dBus_cmd_payload_wr),
                        mask.eq(o_dBus_cmd_payload_mask),
                        address.eq(o_dBus_cmd_payload_address),
                        data.eq(o_dBus_cmd_payload_data),
                        size.eq(o_dBus_cmd_payload_size),
                    ]
                    m.next = 'consider'

            with m.State('consider'):
                assert (self.DMEM_BASE & 0x00FF_FFFF) == 0
                with m.If(address[24:] == (self.DMEM_BASE >> 24)):
                    with m.If(wr):
                        # m.d.sync += Print(Format(
                        #     "[d WR @ {:06x} s{} #{:04b} = {:08x}]",
                        #     dmem_addr, size, mask, data,
                        # ))
                        m.d.comb += [
                            dmem_wp.data.eq(data),
                            dmem_wp.en.eq(mask),
                            dmem_rp.en.eq(0),
                        ]
                        m.d.comb += i_dBus_rsp_ready.eq(1)
                        m.next = 'ready'
                    with m.Else():
                        m.next = 'read'
                with m.Elif((address == self.UART_BASE) & (size == 0)):
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.next = 'ready'
                    with m.If(wr):
                        m.d.comb += uart.wr.p.eq(data[:8])
                        m.d.comb += uart.wr.valid.eq(1)
                        with m.If(~uart.wr.ready):
                            m.d.comb += i_dBus_rsp_ready.eq(0)
                            m.next = 'uart.write.stall'
                    with m.Else():
                        m.d.comb += uart.rd.ready.eq(1)
                        m.d.comb += i_dBus_rsp_data.eq(Mux(uart.rd.valid, uart.rd.p, 0))
                with m.Elif((address == self.UART_BASE) & (size == 1) & ~wr):
                    m.d.comb += uart.rd.ready.eq(1)
                    m.d.comb += i_dBus_rsp_data.eq(Cat(uart.rd.p, uart.rd.valid))
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.next = 'ready'
                with m.Elif((address == self.CSR_EXIT) & (size == 0) & wr & data[0]):
                    m.d.sync += Print("\n! CSR_EXIT signalled -- stopped")
                    m.d.sync += running.eq(0)
                with m.Else():
                    m.d.sync += unhandled_dbus()
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.d.comb += i_dBus_rsp_error.eq(1)
                    m.next = 'ready'

            with m.State('uart.write.stall'):
                m.d.comb += uart.wr.p.eq(data[:8])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.next = 'ready'

            with m.State('read'):
                # m.d.sync += Print(Format(
                #     "[d RD @ {:06x} s{} #{:04b} = {:08x}]",
                #     dmem_addr, size, mask, dmem_rp.data,
                # ))
                m.next = 'ready'
                m.d.comb += i_dBus_rsp_ready.eq(1)
                m.d.comb += i_dBus_rsp_data.eq(dmem_rp.data)

        return m
