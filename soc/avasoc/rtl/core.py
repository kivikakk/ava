from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr, wishbone
from amaranth_soc.csr.wishbone import WishboneCSRBridge
from amaranth_soc.memory import MemoryMap
from amaranth_soc.wishbone.sram import WishboneSRAM

from .imem import WishboneIMem
from .spifr import SPIFlashReader
from .uart import WishboneUART


__all__ = ["Core"]

class Core(wiring.Component):
    # IMEM is backed by SPI flash; we use VexRiscv's built-in I$.
    SPI_IMEM_BASE = 0x0080_0000

    # We're targetting the iCE40UP SPRAM for DMEM, which gives us 128KiB.
    # SPRAM is in 4x 32KiB blocks (16 bits wide, 16,384 deep).
    # SPRAM isn't initialisable[^1]; we init it on startup from IMEM.
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
    IMEM_BASE = 0x8000_0000
    UART_BASE = 0xf000_0000
    CSR_BASE  = 0xf001_0000

    running: Out(1)

    spifr_bus: Out(SPIFlashReader.Signature)

    def elaborate(self, platform):
        m = Module()

        reset = Signal(init=1)
        m.d.sync += reset.eq(0)

        running = Signal(init=1)
        m.d.comb += self.running.eq(running)

        m.submodules.imem = imem = WishboneIMem(base=self.SPI_IMEM_BASE)
        wiring.connect(m, wiring.flipped(self.spifr_bus), imem.spifr_bus)

        m.submodules.imem_arbiter = imem_arbiter = wishbone.Arbiter(addr_width=22, data_width=32, granularity=8, features={"err", "cti", "bte"})
        wiring.connect(m, imem_arbiter.bus, imem.wb_bus)

        m.submodules.ibus = ibus = wishbone.Decoder(addr_width=30, data_width=32,
                                                    granularity=8, features={"err", "cti", "bte"})
        ibus_imem = imem.wb_bus.signature.flip().create()
        ibus_imem.memory_map = MemoryMap(addr_width=24, data_width=8)
        ibus_imem.memory_map.freeze()
        imem_arbiter.add(ibus_imem)
        ibus.add(ibus_imem, name="imem", addr=self.IMEM_BASE)

        m.submodules.dbus = dbus = wishbone.Decoder(addr_width=30, data_width=32,
                                                    granularity=8, features={"err", "cti", "bte"})

        dbus_imem = imem.wb_bus.signature.flip().create()
        dbus_imem.memory_map = MemoryMap(addr_width=24, data_width=8)
        dbus_imem.memory_map.freeze()
        imem_arbiter.add(dbus_imem)
        dbus.add(dbus_imem, name="imem", addr=self.IMEM_BASE)

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

        m.submodules.vexriscv = Instance("VexRiscv",
            i_timerInterrupt=Signal(),
            i_externalInterrupt=Signal(),
            i_softwareInterrupt=Signal(),
            o_iBusWishbone_CYC=ibus.bus.cyc,
            o_iBusWishbone_STB=ibus.bus.stb,
            i_iBusWishbone_ACK=ibus.bus.ack,
            o_iBusWishbone_WE=ibus.bus.we,
            o_iBusWishbone_ADR=ibus.bus.adr,
            i_iBusWishbone_DAT_MISO=ibus.bus.dat_r,
            o_iBusWishbone_DAT_MOSI=ibus.bus.dat_w,
            o_iBusWishbone_SEL=ibus.bus.sel,
            i_iBusWishbone_ERR=ibus.bus.err,
            o_iBusWishbone_CTI=ibus.bus.cti,
            o_iBusWishbone_BTE=ibus.bus.bte,
            o_dBusWishbone_CYC=dbus.bus.cyc,
            o_dBusWishbone_STB=dbus.bus.stb,
            i_dBusWishbone_ACK=dbus.bus.ack,
            o_dBusWishbone_WE=dbus.bus.we,
            o_dBusWishbone_ADR=dbus.bus.adr,
            i_dBusWishbone_DAT_MISO=dbus.bus.dat_r,
            o_dBusWishbone_DAT_MOSI=dbus.bus.dat_w,
            o_dBusWishbone_SEL=dbus.bus.sel,
            i_dBusWishbone_ERR=dbus.bus.err,
            i_clk=ClockSignal(),
            i_reset=reset,
        )

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
