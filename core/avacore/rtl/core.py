from amaranth import Elaboratable, Module
from amaranth.lib import stream

from .uart import UART

__all__ = ["Core"]


class Core(Elaboratable):
    def __init__(self):
        self.plat_uart = None

    def elaborate(self, platform):
        m = Module()

        m.submodules.uart = self.uart = uart = UART(self.plat_uart)
        m.d.sync += [
            uart.wr.payload.eq(uart.rd.payload),
            uart.wr.valid.eq(uart.rd.valid),
            uart.rd.ready.eq(uart.wr.ready),
        ]

        return m
