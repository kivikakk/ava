from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth.lib.memory import Memory

from .uart import UART


__all__ = ["Core"]

class Core(wiring.Component):
    # We're targetting the iCE40UP SPRAM for DMEM, which gives us 128KiB.
    # SPRAM is in 4x 32KiB blocks (16 bits wide, 16,384 deep).
    # Importantly, it is *not* initialisable; we initialise SPRAM from BRAM. (If
    # it grows too large, we can initialise from flash or something.)
    # BSS and minimum stack size availability are asserted in the linker script.
    DMEM_BYTES = 128 * 1024

    DMEM_BASE = 0x4000_0000
    UART_BASE = 0x8000_0000
    CSR_EXIT  = 0x8000_ffff

    running: Out(1)

    def __init__(self, *, imem, dmem, uart):
        super().__init__()
        self._imem = imem
        self._dmem = dmem
        self._uart = uart

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
            i_reset=ResetSignal(),
        )

        m.submodules.uart = uart = UART(
            self._uart, baud=115_200, tx_fifo_depth=16, rx_fifo_depth=32)

        m.submodules.imem = imem = Memory(shape=32, depth=len(self._imem), init=self._imem)
        imem_rp = imem.read_port()

        imem_fetch_rem = Signal(range(8))

        with m.FSM():
            with m.State('init'):
                m.d.comb += i_iBus_cmd_ready.eq(1)
                with m.If(o_iBus_cmd_valid):
                    m.d.sync += Assert(o_iBus_cmd_payload_size == 5)  # i.e. 2**5 == 32 bytes
                    m.d.sync += imem_rp.addr.eq(o_iBus_cmd_payload_address >> 2)
                    m.d.sync += imem_fetch_rem.eq(7)
                    m.next = 'read.stall'

            with m.State('read.stall'):
                m.d.sync += imem_rp.addr.eq(imem_rp.addr + 1)
                m.next = 'read.present'

            with m.State('read.present'):
                m.d.sync += imem_rp.addr.eq(imem_rp.addr + 1)
                m.d.sync += imem_fetch_rem.eq(imem_fetch_rem - 1)
                m.d.comb += i_iBus_rsp_valid.eq(1)
                m.d.comb += i_iBus_rsp_payload_data.eq(imem_rp.data)
                with m.If(imem_fetch_rem == 0):
                    m.next = 'init'

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
                    m.next = 'ready'
                with m.Else():
                    m.d.sync += dmem_init_rp.addr.eq(dmem_init_rp.addr + 1)
                    m.next = 'init.wait'

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
