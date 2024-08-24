from dataclasses import dataclass

from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .core import Core

__all__ = ["Top"]


HELLO_AVC = [
    0x01, 0x02, 0x00,
    0x20, 0x00,
    0x01, 0x04, 0x00,
    0x20, 0x01,
    0x0a, 0x00,
    0x0a, 0x01,
    0xa5,
    0x80,
    0x82,
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

        rst = Signal()
        m.d.sync += rst.eq(0)

        # core = Core(code=HELLO_AVC)

        match platform:
            case icebreaker():
                # core.plat_uart = platform.request("uart")

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

                # core.plat_uart = FakeUart(
                #     rx=FakeUartPin(i=self.uart_rx),
                #     tx=FakeUartPin(o=self.uart_tx))

        # m.submodules.core = ResetInserter(rst)(core)

        o_iBus_cmd_valid = Signal()
        i_iBus_cmd_ready = Signal()
        o_iBus_cmd_payload_pc = Signal()
        i_iBus_rsp_valid = Signal()
        i_iBus_rsp_payload_error = Signal()
        i_iBus_rsp_payload_inst = Signal()
        i_timerInterrupt = Signal()
        i_externalInterrupt = Signal()
        i_softwareInterrupt = Signal()
        o_dBus_cmd_valid = Signal()
        i_dBus_cmd_ready = Signal()
        o_dBus_cmd_payload_wr = Signal()
        o_dBus_cmd_payload_mask = Signal()
        o_dBus_cmd_payload_address = Signal()
        o_dBus_cmd_payload_data = Signal()
        o_dBus_cmd_payload_size = Signal()
        i_dBus_rsp_ready = Signal()
        i_dBus_rsp_error = Signal()
        i_dBus_rsp_data = Signal()
        i_clk = Signal()
        i_reset = Signal()

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
            i_clk=i_clk,
            i_reset=i_reset,
        )

        return m
