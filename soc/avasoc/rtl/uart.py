from amaranth import *
from amaranth.lib import stream
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.wiring import Component, In, Out
from amaranth_stdio.serial import AsyncSerial


__all__ = ["UART"]


class UART(Component):
    wr: In(stream.Signature(8))
    rd: Out(stream.Signature(8))
    rd_overrun: Out(1)

    _plat_uart: object
    _baud: int
    _tx_fifo_depth: int
    _rx_fifo_depth: int

    def __init__(self, plat_uart, *, tx_fifo_depth, rx_fifo_depth, baud):
        self._plat_uart = plat_uart
        self._baud = baud
        self._tx_fifo_depth = tx_fifo_depth
        self._rx_fifo_depth = rx_fifo_depth
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
        m.submodules.tx_fifo = tx_fifo = SyncFIFOBuffered(width=8, depth=self._tx_fifo_depth)
        m.d.comb += [
            tx_fifo.w_data.eq(self.wr.payload),
            tx_fifo.w_en.eq(self.wr.valid),
            self.wr.ready.eq(tx_fifo.w_rdy),
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
        m.submodules.rx_fifo = rx_fifo = SyncFIFOBuffered(width=8, depth=self._rx_fifo_depth)
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
                with m.If(serial.rx.err.as_value() == 0):
                    m.d.sync += [
                        rx_fifo.w_data.eq(serial.rx.data),
                        rx_fifo.w_en.eq(1),
                    ]
                    with m.If(~rx_fifo.w_rdy):
                        m.d.sync += Print("\n!! UART rd buffer overrun !!")
                        m.d.sync += self.rd_overrun.eq(1)
                m.next = "idle"

            m.d.comb += serial.rx.ack.eq(fsm.ongoing("idle"))

        return m
