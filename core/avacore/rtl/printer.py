from amaranth import *
from amaranth.lib import stream
from amaranth.lib.wiring import Component, In, Out

from .divider import StreamingDivider

__all__ = ["Printer"]


class PrinterInteger(Component):
    w_stream: In(stream.Signature(signed(32)))
    r_stream: Out(stream.Signature(8))

    def elaborate(self, platform):
        m = Module()

        # Early experiments show rapow=2 gives best overall timing and LC use:
        # slightly better than 1, and significantly better than >= 3.
        # I imagine that over time 1 might become preferable again, as routing
        # becomes more congested.
        #
        # abits=32 -- we need to reach 2**31 when printing -2**31
        # dbits=30 -- only needs to reach 1e9.
        m.submodules.sdivider = sdivider = \
            StreamingDivider(abits=32, dbits=30, sign=False, rapow=2)

        n = Signal(32)
        digits = Signal(range(20))
        divisors = Array(10**n for n in range(1, 11))

        with m.FSM():
            with m.State('init'):
                m.d.comb += self.w_stream.ready.eq(1)
                with m.If(self.w_stream.valid):
                    m.d.sync += n.eq(self.w_stream.p)
                    m.next = 'sign'

            with m.State('sign'):
                with m.If(n[-1]):
                    m.d.comb += self.r_stream.p.eq(ord(b'-'))
                with m.Else():
                    m.d.comb += self.r_stream.p.eq(ord(b' '))
                m.d.comb += self.r_stream.valid.eq(1)
                with m.If(self.r_stream.ready):
                    m.d.sync += [
                        n.eq(Mux(n[-1], -n.as_signed(), n)),
                        digits.eq(1),
                    ]
                    m.next = 'count'

            with m.State('count'):
                with m.If(divisors[digits-1] <= n):
                    m.d.sync += digits.eq(digits + 1)
                with m.Else():
                    m.next = 'each'

            with m.State('each'):
                with m.If(digits == 0):
                    m.d.comb += [
                        self.r_stream.p.eq(ord(b' ')),
                        self.r_stream.valid.eq(1),
                    ]
                    with m.If(self.r_stream.ready):
                        m.next = 'init'
                with m.Elif(digits == 1):
                    m.d.comb += [
                        self.r_stream.p.eq(ord(b'0') + n),
                        self.r_stream.valid.eq(1),
                    ]
                    with m.If(self.r_stream.ready):
                        m.d.sync += digits.eq(0)
                with m.Else():
                    m.d.comb += [
                        sdivider.w_stream.p.a.eq(n),
                        sdivider.w_stream.p.d.eq(divisors[digits-2]),
                        sdivider.w_stream.valid.eq(1),
                    ]
                    with m.If(sdivider.w_stream.ready):
                        m.next = 'dividing'

            with m.State('dividing'):
                with m.If(sdivider.r_stream.valid):
                    m.d.sync += Assert(sdivider.r_stream.p.z == 0)
                    m.d.comb += [
                        self.r_stream.p.eq(ord(b'0') + sdivider.r_stream.p.q),
                        self.r_stream.valid.eq(1),
                    ]
                    with m.If(self.r_stream.ready):
                        m.d.comb += sdivider.r_stream.ready.eq(1)
                        m.d.sync += [
                            n.eq(sdivider.r_stream.p.r),
                            digits.eq(digits - 1),
                        ]
                        m.next = 'each'

        return m
