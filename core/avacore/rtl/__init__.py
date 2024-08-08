from dataclasses import dataclass

from amaranth import Module, ResetInserter, Signal
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from ..targets import cxxrtl, icebreaker
from .core import Core

__all__ = ["Top"]


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

        core = Core()

        match platform:
            case icebreaker():
                core.plat_uart = platform.request("uart")

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

                core.plat_uart = FakeUart(
                    rx=FakeUartPin(i=self.uart_rx),
                    tx=FakeUartPin(o=self.uart_tx))

        m.submodules.core = ResetInserter(rst)(core)

        return m
