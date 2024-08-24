from dataclasses import dataclass

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.memory import Memory
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .uart import UART

__all__ = ["Top"]


CODE = [
    0x80000537,  # lui a0, 0x80000
    0x3e800593,  # li a1, 1000
    0x00b52023,  # sw a1, 0(a0)
    0x7d000593,  # li a1, 2000
    0x00b52023,  # sw a1, 0(a0)
    0xfedff06f,  # jal x0, -20
]

class Top(wiring.Component):
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

        m.submodules.imem = imem = Memory(shape=32, depth=len(CODE), init=CODE)
        imem_rp = imem.read_port()

        with m.FSM():
            with m.State('init'):
                m.d.comb += i_iBus_cmd_ready.eq(1)
                with m.If(o_iBus_cmd_valid):
                    m.d.sync += imem_rp.addr.eq(o_iBus_cmd_payload_pc)
                    m.next = 'read.wait'

            with m.State('read.wait'):
                m.next = 'read.wait2'
            with m.State('read.wait2'):
                m.next = 'read.present'

            with m.State('read.present'):
                m.d.comb += i_iBus_rsp_valid.eq(1)
                m.d.comb += i_iBus_rsp_payload_inst.eq(imem_rp.data)
                m.next = 'init'

        wr = Signal()
        mask = Signal(4)
        address = Signal(32)
        data = Signal(32)
        size = Signal(2)

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
                    m.next = 'write.wr'

            with m.State('write.wr'):
                m.d.comb += uart.wr.p.eq(wr)
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.mask'

            with m.State('write.mask'):
                m.d.comb += uart.wr.p.eq(mask)
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.address0'

            with m.State('write.address0'):
                m.d.comb += uart.wr.p.eq(address[0:8])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.address1'

            with m.State('write.address1'):
                m.d.comb += uart.wr.p.eq(address[8:16])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.address2'

            with m.State('write.address2'):
                m.d.comb += uart.wr.p.eq(address[16:24])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.address3'

            with m.State('write.address3'):
                m.d.comb += uart.wr.p.eq(address[24:32])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.data0'

            with m.State('write.data0'):
                m.d.comb += uart.wr.p.eq(data[0:8])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.data1'

            with m.State('write.data1'):
                m.d.comb += uart.wr.p.eq(data[8:16])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.data2'

            with m.State('write.data2'):
                m.d.comb += uart.wr.p.eq(data[16:24])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.data3'

            with m.State('write.data3'):
                m.d.comb += uart.wr.p.eq(data[24:32])
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'write.size'

            with m.State('write.size'):
                m.d.comb += uart.wr.p.eq(size)
                m.d.comb += uart.wr.valid.eq(1)
                with m.If(uart.wr.ready):
                    m.next = 'finish'

            with m.State('finish'):
                m.d.comb += i_dBus_rsp_ready.eq(1)
                m.next = 'init'

        return m
