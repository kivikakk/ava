from amaranth import *
from amaranth.lib import stream
from amaranth.lib.wiring import Component, In, Out


__all__ = ["Printer"]


class Printer(Component):
    w_stream: In(stream.Signature(32))
    r_stream: Out(stream.Signature(8))

    def elaborate(self, platform):
        m = Module()

        datum = Signal(signed(16))

        with m.FSM():
            with m.State('init'):
                m.d.comb += self.w_stream.ready.eq(1)
                with m.If(self.w_stream.valid):
                    m.d.sync += datum.eq(self.w_stream.p)
                    m.next = 'sign'

            with m.State('sign'):
                with m.If(datum[15]):
                    m.d.comb += self.r_stream.p.eq(ord(b'-'))
                with m.Else():
                    m.d.comb += self.r_stream.p.eq(ord(b' '))
                m.d.comb += self.r_stream.valid.eq(1)
                with m.If(self.r_stream.ready):
                    m.d.sync += datum.eq(Mux(datum[15], -datum, datum))
                    m.next = 'rest'

            with m.State('rest'):
                m.d.comb += self.r_stream.p.eq(ord(b'0') + datum)
                m.d.comb += self.r_stream.valid.eq(1)
                with m.If(self.r_stream.ready):
                    m.next = 'trailing'

            with m.State('trailing'):
                m.d.comb += self.r_stream.p.eq(ord(b' '))
                m.d.comb += self.r_stream.valid.eq(1)
                with m.If(self.r_stream.ready):
                    m.next = 'init'

        return m
