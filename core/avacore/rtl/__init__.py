import struct
from dataclasses import dataclass
from itertools import chain
from pathlib import Path

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .uart import UART


__all__ = ["Top"]


def wonk32(path):
    b = path.read_bytes()
    while len(b) % 4 != 0:
        b += b'\0'
    return list(chain.from_iterable(struct.iter_unpack('<L', b)))


basic = Path(__file__).parent.parent.parent.parent / "basic"
# vexriscv will always read one past a jump.
IMEM = wonk32(basic / "zig-out" / "bin" / "avacore.imem.bin") + [0]
DMEM = wonk32(basic / "zig-out" / "bin" / "avacore.dmem.bin")

class Top(wiring.Component):
    DMEM_BYTES       = 4096  # Must correspond to what we set our stack pointer to in crt0.S.
    DMEM_STACK_BYTES = 1024  # XXX: we should be able to determine this with Zig.

    DMEM_BASE = 0x4000_0000
    UART_BASE = 0x8000_0000
    CSR_EXIT  = 0x8000_ffff

    def __init__(self, platform):
        if isinstance(platform, cxxrtl):
            super().__init__({
                "uart_rx": In(1),
                "uart_tx": Out(1),
            })
        else:
            super().__init__({})

    def elaborate(self, platform):
        m = Module()

        # TODO: reset other things we instantiate here/move all down one.
        rst = Signal()
        m.d.sync += rst.eq(0)

        o_iBus_cmd_valid = Signal()
        i_iBus_cmd_ready = Signal()
        o_iBus_cmd_payload_pc = Signal(32)
        i_iBus_rsp_valid = Signal()
        i_iBus_rsp_payload_error = Signal()
        i_iBus_rsp_payload_inst = Signal(32)
        i_timerInterrupt = Signal()
        i_externalInterrupt = Signal()
        i_softwareInterrupt = Signal()
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
            o_iBus_cmd_valid=o_iBus_cmd_valid,
            i_iBus_cmd_ready=i_iBus_cmd_ready,
            o_iBus_cmd_payload_pc=o_iBus_cmd_payload_pc,
            i_iBus_rsp_valid=i_iBus_rsp_valid,
            i_iBus_rsp_payload_error=i_iBus_rsp_payload_error,
            i_iBus_rsp_payload_inst=i_iBus_rsp_payload_inst,
            i_timerInterrupt=i_timerInterrupt,
            i_externalInterrupt=i_externalInterrupt,
            i_softwareInterrupt=i_softwareInterrupt,
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
            i_clk=ClockSignal("sync"),
            i_reset=rst,
        )

        match platform:
            case icebreaker():
                plat_uart = platform.request("uart")

                btn = platform.request("button")
                with m.If(btn.i):
                    m.d.sync += rst.eq(1)

            case cxxrtl():
                @dataclass
                class FakeUartPin:
                    i: Signal = None
                    o: Signal = None

                @dataclass
                class FakeUart:
                    rx: FakeUartPin
                    tx: FakeUartPin

                plat_uart = FakeUart(
                    rx=FakeUartPin(i=self.uart_rx),
                    tx=FakeUartPin(o=self.uart_tx))

        m.submodules.uart = uart = UART(plat_uart)

        m.submodules.imem = imem = Memory(shape=32, depth=len(IMEM), init=IMEM)
        imem_rp = imem.read_port()

        with m.FSM():
            with m.State('init'):
                # Currently using GenSmallest which sets IBusSimplePlugin.cmdForkPersistence=false,
                # so we ack at once and save anything we need.
                m.d.comb += i_iBus_cmd_ready.eq(1)
                with m.If(o_iBus_cmd_valid):
                    m.d.sync += imem_rp.addr.eq(o_iBus_cmd_payload_pc >> 2)
                    m.next = 'read.wait'

            with m.State('read.wait'):
                m.next = 'read.present'

            with m.State('read.present'):
                m.d.comb += i_iBus_rsp_valid.eq(1)
                m.d.comb += i_iBus_rsp_payload_inst.eq(imem_rp.data)
                m.next = 'init'

        assert self.DMEM_BYTES % 4 == 0
        assert len(DMEM) * 4 + self.DMEM_STACK_BYTES <= self.DMEM_BYTES
        m.submodules.dmem = dmem = Memory(shape=32, depth=self.DMEM_BYTES // 4, init=DMEM)
        dmem_wp = dmem.write_port(granularity=8)
        dmem_rp = dmem.read_port(transparent_for=[dmem_wp])

        wr = Signal()
        mask = Signal(4)
        address = Signal(32)
        data = Signal(32)
        size = Signal(2)

        dmem_addr = Signal.like(dmem_wp.addr)
        m.d.comb += dmem_addr.eq(address >> 2)

        unhandled_dbus = lambda: Print(Format(
            "unhandled dBus {} at {:08x} mask {:04b} size {} (data {:08x})",
            wr, address, mask, size, data,
        ))

        with m.FSM():
            with m.State('init'):
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
                            dmem_wp.addr.eq(dmem_addr),
                            dmem_wp.data.eq(data),
                            dmem_wp.en.eq(mask),
                        ]
                        m.d.comb += i_dBus_rsp_ready.eq(1)
                        m.next = 'init'
                    with m.Else():
                        m.d.comb += dmem_rp.addr.eq(dmem_addr)
                        m.next = 'read'
                with m.Elif((address == self.UART_BASE) & (size == 0)):
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.next = 'init'
                    with m.If(wr):
                        m.d.comb += uart.wr.p.eq(data[:8])
                        m.d.comb += uart.wr.valid.eq(1)
                    with m.Else():
                        m.d.comb += uart.rd.ready.eq(1)
                        m.d.comb += i_dBus_rsp_data.eq(Mux(uart.rd.valid, uart.rd.p, 0))
                with m.Elif((address == self.UART_BASE) & (size == 1) & ~wr):
                    m.d.comb += uart.rd.ready.eq(1)
                    m.d.comb += i_dBus_rsp_data.eq(Cat(uart.rd.p, uart.rd.valid))
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.next = 'init'
                with m.Elif((address == self.CSR_EXIT) & (size == 0) & wr & data[0]):
                    m.d.sync += Print("\nCSR_EXIT signalled -- stopped")
                    m.next = 'stopped'
                with m.Else():
                    m.d.sync += unhandled_dbus()
                    m.d.comb += i_dBus_rsp_ready.eq(1)
                    m.d.comb += i_dBus_rsp_error.eq(1)
                    m.next = 'init'

            with m.State('read'):
                # m.d.sync += Print(Format(
                #     "[d RD @ {:06x} s{} #{:04b} = {:08x}]",
                #     dmem_addr, size, mask, dmem_rp.data,
                # ))
                m.next = 'init'
                m.d.comb += i_dBus_rsp_ready.eq(1)
                m.d.comb += i_dBus_rsp_data.eq(dmem_rp.data)

            with m.State('stopped'):
                # TODO: this is only the dmem controller. signal higher and stop there.
                pass

        return m
