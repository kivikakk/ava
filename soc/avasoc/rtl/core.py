from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr, wishbone
from amaranth_soc.csr.wishbone import WishboneCSRBridge
from amaranth_soc.wishbone.sram import WishboneSRAM

from .imem import IMem
from .spifr import SPIFlashReader
from .uart import WishboneUART


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
    #      that produce the right $memrd_v2/$memwr_v2s, and wire up the
    #      ports[^2].
    #
    # [^2]: this is no longer true now that we use amaranth-soc's WishboneSRAM.
    #       Unhacking would require hacking WishboneSRAM instead (to produce
    #       those instances).
    DMEM_BYTES = 128 * 1024

    DMEM_BASE = 0x4000_0000
    UART_BASE = 0xf000_0000
    CSR_BASE  = 0xf001_0000

    running: Out(1)

    spifr_bus: Out(SPIFlashReader.Signature)

    def __init__(self, *, dmem):
        super().__init__()
        self._dmem = dmem

    def elaborate(self, platform):
        m = Module()

        running = Signal(init=1)
        m.d.comb += self.running.eq(running)

        # TODO: redo IMEM with Wishbone. Note that IBusCachedPlugin's Wishbone
        # bridge (i.e. InstructionCacheMemBus.toWishbone) uses incrementing
        # burst read, which dovetails well with the SPI flash protocol, but
        # requires a rework of the interleaving bits and pieces.
        m.submodules.imem = imem = IMem(base=self.SPI_IMEM_BASE)
        wiring.connect(m, wiring.flipped(self.spifr_bus), imem.spifr_bus)

        m.submodules.dbus = dbus = wishbone.Decoder(addr_width=30, data_width=32,
                                                    granularity=8, features={"err"})

        m.submodules.sram = sram = WishboneSRAM(size=self.DMEM_BYTES,
                                                data_width=32, granularity=8, init=None)
        dbus.add(sram.wb_bus, name="dmem", addr=self.DMEM_BASE)

        m.submodules.uart = uart = WishboneUART(self._uart, baud=1_500_000,
                                                tx_fifo_depth=32, rx_fifo_depth=32)
        dbus.add(uart.wb_bus, name="uart", addr=self.UART_BASE)

        m.submodules.csrs = csrs = CSRPeripheral()
        m.submodules.csr_bridge = csr_bridge = WishboneCSRBridge(csrs.bus, data_width=32)
        dbus.add(csr_bridge.wb_bus, name="csr_bridge", addr=self.CSR_BASE)
        with m.If(csrs.stop):
            m.d.sync += running.eq(0)

        m.submodules.dmem_init = dmem_init = DMemInit(self._dmem,
                                                      dmem_base=self.DMEM_BASE,
                                                      dmem_bytes=self.DMEM_BYTES)

        vex_bus = dbus.bus.signature.create()
        with m.If(~dmem_init.ready):
            wiring.connect(m, dbus.bus, wiring.flipped(dmem_init.wb_bus))
        with m.Else():
            wiring.connect(m, dbus.bus, wiring.flipped(vex_bus))

        m.submodules.vexriscv = Instance("VexRiscv",
            i_timerInterrupt=Signal(),
            i_externalInterrupt=Signal(),
            i_softwareInterrupt=Signal(),
            o_iBus_cmd_valid=imem.cmd.valid,
            i_iBus_cmd_ready=imem.cmd.ready,
            o_iBus_cmd_payload_address=imem.cmd.p.address,
            o_iBus_cmd_payload_size=imem.cmd.p.size,
            i_iBus_rsp_valid=imem.rsp.valid,
            i_iBus_rsp_payload_data=imem.rsp.p.data,
            i_iBus_rsp_payload_error=imem.rsp.p.error,
            o_dBusWishbone_CYC=vex_bus.cyc,
            o_dBusWishbone_STB=vex_bus.stb,
            i_dBusWishbone_ACK=vex_bus.ack,
            o_dBusWishbone_WE=vex_bus.we,
            o_dBusWishbone_ADR=vex_bus.adr,
            i_dBusWishbone_DAT_MISO=vex_bus.dat_r,
            o_dBusWishbone_DAT_MOSI=vex_bus.dat_w,
            o_dBusWishbone_SEL=vex_bus.sel,
            i_dBusWishbone_ERR=vex_bus.err,
            i_clk=ClockSignal(),
            i_reset=~dmem_init.ready,
        )

        return m


class DMemInit(wiring.Component):
    wb_bus: In(wishbone.bus.Signature(addr_width=30, data_width=32,
                                      granularity=8, features={"err"}))
    ready: Out(1)

    def __init__(self, dmem, *, dmem_base, dmem_bytes):
        self._dmem = dmem
        self._dmem_base = dmem_base
        self._dmem_bytes = dmem_bytes
        super().__init__()

    def elaborate(self, platform):
        m = Module()

        m.submodules.mem = mem = Memory(shape=32, depth=len(self._dmem), init=self._dmem)
        read_port = mem.read_port()

        address = Signal.like(self.wb_bus.adr)
        m.d.comb += [
            self.wb_bus.adr.eq((self._dmem_base >> 2) | address),
            self.wb_bus.sel.eq(0b1111),
            self.wb_bus.we.eq(1),
        ]

        with m.FSM():
            with m.State('init.wait'):
                m.next = 'init.write'

            with m.State('init.write'):
                m.d.comb += [
                    self.wb_bus.dat_w.eq(read_port.data),
                    self.wb_bus.cyc.eq(1),
                    self.wb_bus.stb.eq(1),
                ]
                with m.If(self.wb_bus.ack):
                    m.d.sync += address.eq(address + 1)
                    m.d.sync += read_port.addr.eq(read_port.addr + 1)
                    with m.If(address == len(self._dmem) - 1):
                        m.next = 'zero'
                    with m.Else():
                        m.next = 'init.wait'

            with m.State('zero'):
                m.d.comb += [
                    self.wb_bus.dat_w.eq(0),
                    self.wb_bus.cyc.eq(1),
                    self.wb_bus.stb.eq(1),
                ]
                with m.If(self.wb_bus.ack):
                    m.d.sync += address.eq(address + 1)
                    with m.If(address == (self._dmem_bytes // 4) - 1):
                        m.d.sync += self.ready.eq(1)
                        m.next = 'ready'

            with m.State('ready'):
                pass
        return m


class CSRPeripheral(wiring.Component):
    bus: In(csr.Signature(addr_width=4, data_width=8))

    stop: Out(1)

    def __init__(self):
        regs = csr.Builder(addr_width=4, data_width=8)
        self._exit = regs.add("exit", csr.Register(csr.Field(csr.action.W, 1), access="w"), offset=0)

        self._bridge = csr.Bridge(regs.as_memory_map())
        super().__init__()
        self.bus.memory_map = self._bridge.bus.memory_map

    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.bus), self._bridge.bus)

        with m.If(self._exit.f.w_stb):
            m.d.sync += Print("\n! EXIT signalled -- stopped")
            m.d.sync += self.stop.eq(1)

        return m
