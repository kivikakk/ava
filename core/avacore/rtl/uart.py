from amaranth import *
from amaranth.lib import stream
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.wiring import Component, In, Out
from amaranth_stdio.serial import AsyncSerial


__all__ = ["UART"]


class UART(Component):
    wr: In(stream.Signature(8))
    rd: Out(stream.Signature(8))

    plat_uart: object
    baud: int

    def __init__(self, plat_uart, baud=115_200):
        self.plat_uart = plat_uart
        self.baud = baud
        super().__init__()

    def elaborate(self, platform):
        m = Module()

        if getattr(platform, "simulation", False):
            # Blackboxed in tests.
            return m

        freq = platform.default_clk_frequency

        m.submodules.serial = serial = AsyncSerial(
            divisor=int(freq // self._baud),
            pins=self._plat_uart)

        # tx
        m.submodules.tx_fifo = tx_fifo = SyncFIFOBuffered(width=8, depth=8)
        m.d.comb += [
            tx_fifo.w_data.eq(self.wr.payload),
            tx_fifo.w_en.eq(self.wr.valid),
        ]
        with m.FSM() as fsm:
            with m.State("idle"):
                with m.If(serial.tx.rdy & tx_fifo.r_rdy):
                    m.d.sync += serial.tx.data.eq(tx_fifo.r_data)
                    m.next = "wait"

            with m.State("wait"):
                m.next = "idle"

            m.d.comb += [
                serial.tx.ack.eq(fsm.ongoing("wait")),
                tx_fifo.r_en.eq(fsm.ongoing("wait")),
            ]

        # rx
        m.submodules.rx_fifo = rx_fifo = SyncFIFOBuffered(width=8, depth=8)
        m.d.comb += [
            self.rd.valid.eq(rx_fifo.r_rdy),
            self.rd.payload.eq(rx_fifo.r_data),
            rx_fifo.r_en.eq(self.rd.ready),
        ]
        with m.FSM() as fsm:
            with m.State("idle"):
                m.d.sync += rx_fifo.w_en.eq(0)
                with m.If(serial.rx.rdy):
                    m.next = "read"

            with m.State("read"):
                m.d.sync += [
                    _rx_fifo.w_data.eq(serial.rx.data),
                    _rx_fifo.w_en.eq(1),
                ]
                m.next = "idle"

            m.d.comb += serial.rx.ack.eq(fsm.ongoing("idle"))

        return m
