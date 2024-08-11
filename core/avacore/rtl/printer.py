from amaranth import *
from amaranth.lib import stream
from amaranth.lib.wiring import Component, In, Out


__all__ = ["Printer"]


class Printer(Component):
    w_stream: In(stream.Signature(32))
    r_stream: Out(stream.Signature(8))

    def elaborate(self, platform):
        m = Module()

        n = Signal(16)

        d = Signal(range(20))  # digit counter
        v = Signal(range(100001))  # divisor

        with m.FSM():
            with m.State('init'):
                m.d.comb += self.w_stream.ready.eq(1)
                with m.If(self.w_stream.valid):
                    m.d.sync += n.eq(self.w_stream.p)
                    m.next = 'sign'

            with m.State('sign'):
                with m.If(n[15]):
                    m.d.comb += self.r_stream.p.eq(ord(b'-'))
                with m.Else():
                    m.d.comb += self.r_stream.p.eq(ord(b' '))
                m.d.comb += self.r_stream.valid.eq(1)
                with m.If(self.r_stream.ready):
                    m.d.sync += [
                        n.eq(Mux(n[15], -n.as_signed(), n)),
                        d.eq(1),
                        v.eq(10),
                    ]
                    m.next = 'count'

            with m.State('count'):
                with m.If(v <= n):
                    m.d.sync += [
                        d.eq(d + 1),
                        v.eq(v * 10),
                    ]
                with m.Else():
                    m.d.sync += v.eq(v // 10)
                    m.next = 'each'

            with m.State('each'):
                with m.If(d == 0):
                    m.d.comb += [
                        self.r_stream.p.eq(ord(b' ')),
                        self.r_stream.valid.eq(1),
                    ]
                    with m.If(self.r_stream.ready):
                        m.next = 'init'
                with m.Else():
                    m.d.comb += [
                        self.r_stream.p.eq(ord(b'0') + (n // v)),
                        self.r_stream.valid.eq(1),
                    ]
                    with m.If(self.r_stream.ready):
                        m.d.sync += [
                            n.eq(n - (n // v) * v),
                            v.eq(v // 10),
                            d.eq(d - 1),
                        ]

        return m
