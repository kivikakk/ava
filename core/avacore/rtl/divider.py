# This file is a port of the following, and therefore is excluded from the
# project-wide GPLv3+ license and instead follows its.
#
# Source: https://github.com/VLSI-EDA/PoC/blob/894d3cd0/src/arith/arith_div.vhdl
#
# Verbatim copyright from the source follows.
#
# =============================================================================
# Copyright 2007-2016 Technische Universität Dresden - Germany,
#                     Chair of VLSI-Design, Diagnostics and Architecture
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================

from amaranth import *
from amaranth.lib import data, stream
from amaranth.lib.fifo import SyncFIFO
from amaranth.lib.wiring import Component, In, Out
from amaranth.utils import ceil_log2


__all__ = ["StreamingDivider", "Divider"]


class StreamingDivider(Component):
    """
    Provides a stream-based interface to Divider.

    Additionally allows signed operation.
    """

    @staticmethod
    def request_layout(abits, dbits, sign):
        return data.StructLayout({
            "a": signed(abits) if sign else unsigned(abits),
            "d": signed(dbits) if sign else unsigned(dbits),
        })

    @staticmethod
    def response_layout(abits, dbits, sign):
        return data.StructLayout({
            "q": signed(abits) if sign else unsigned(abits),
            "r": signed(dbits) if sign else unsigned(dbits),
            "z": 1,
        })

    @staticmethod
    def reqstate_layout(dbits):
        return data.StructLayout({
            "an": 1,
            "d": signed(dbits),
        })

    def __init__(self, *, abits, dbits, sign, rapow=1, pipelined=False):
        super().__init__({
            "w_stream": In(stream.Signature(self.request_layout(abits, dbits, sign))),
            "r_stream": Out(stream.Signature(self.response_layout(abits, dbits, sign))),
        })
        self.abits = abits
        self.dbits = dbits
        self.sign = sign
        self.rapow = rapow
        self.pipelined = pipelined

        self.divider = Divider(abits=abits, dbits=dbits, rapow=rapow, pipelined=pipelined)

    def elaborate(self, platform):
        m = Module()

        m.submodules.divider = divider = self.divider
        depth = divider.steps if self.pipelined else 1

        # TODO: Can probably use *Buffered in both here?
        if self.sign:
            reqstate = self.reqstate_layout(self.dbits)
        else:
            reqstate = data.StructLayout({})
        m.submodules.reqs = reqs = SyncFIFO(width=reqstate.size, depth=depth)

        response = self.response_layout(self.abits, self.dbits, self.sign)
        m.submodules.resps = resps = SyncFIFO(width=response.size, depth=depth)

        can_accept = (reqs.level + resps.level) < depth
        m.d.comb += self.w_stream.ready.eq(can_accept)

        with m.If(can_accept & self.w_stream.valid):
            m.d.comb += [
                divider.a.eq(self.w_stream.p.a),
                divider.d.eq(self.w_stream.p.d),
                divider.start.eq(1),
            ]

            m.d.comb += reqs.w_en.eq(1)

            if self.sign:
                req = Signal(reqstate)
                m.d.comb += [
                    req.an.eq(self.w_stream.p.a[-1]),
                    req.d.eq(self.w_stream.p.d),
                    reqs.w_data.eq(req),
                    divider.a.eq(Mux(
                        self.w_stream.p.a[-1],
                        -self.w_stream.p.a,
                        self.w_stream.p.a,
                    )),
                    divider.d.eq(Mux(
                        self.w_stream.p.d[-1],
                        -self.w_stream.p.d,
                        self.w_stream.p.d,
                    )),
                ]

        with m.If(reqs.r_rdy & divider.ready):
            m.d.sync += Assert(resps.w_rdy)
            resp = Signal(response)
            m.d.comb += [
                resp.q.eq(divider.q),
                resp.r.eq(divider.r),
                resp.z.eq(divider.z),
                resps.w_data.eq(resp),
                resps.w_en.eq(1),
            ]

            m.d.comb += reqs.r_en.eq(1)

            if self.sign:
                req = reqstate(reqs.r_data)
                with m.If(req.an ^ req.d[-1]):
                    m.d.comb += resp.q.eq(-divider.q)

                with m.If(req.an):
                    m.d.comb += resp.r.eq(-divider.r)

        m.d.comb += [
            self.r_stream.p.eq(resps.r_data),
            self.r_stream.valid.eq(resps.r_rdy),
            resps.r_en.eq(self.r_stream.ready),
        ]

        return m


class Divider(Component):
    # Docstring per the original.
    """
    Implementation of a Non-Performing restoring divider with a configurable radix.
    The multi-cycle division is controlled by 'start' / 'rdy'. A new division is
    started by asserting 'start'. The result Q = A/D is available when 'rdy'
    returns to '1'. A division by zero is identified by output Z. The Q and R
    outputs are undefined in this case.
    """

    def __init__(self, *, abits, dbits, rapow=1, pipelined=False):
        assert abits > 0
        assert dbits > 0
        assert rapow >= 1

        self.abits = abits
        self.dbits = dbits
        self.rapow = rapow
        self.pipelined = pipelined

        self.steps = (abits + rapow - 1) // rapow

        super().__init__({
            "start": In(1),
            "ready": Out(1),
            "a": In(abits),   # dividend
            "d": In(dbits),   # divisor
            "q": Out(abits),  # quotient
            "r": Out(dbits),  # remainder
            "z": Out(1),      # div/0!
        })

    def elaborate(self, platform):
        m = Module()

        steps = self.steps
        depth = steps if self.pipelined else 0
        trunk_bits = (steps - 1) * self.rapow
        active_bits = self.dbits + self.rapow

        residue = unsigned(active_bits + trunk_bits)
        divisor = unsigned(self.dbits)

        def div_step(av, dv):
            assert len(av) == residue.width
            assert len(dv) == divisor.width

            res = Signal(residue)

            win = av[trunk_bits + self.rapow:]
            assert len(win) == self.dbits

            for i in range(self.rapow - 1, -1, -1):
                dif = (Cat(av[trunk_bits+i], win) - dv)[:self.dbits+1]
                win = Mux(~dif[-1],
                    dif[:-1],
                    Cat(av[trunk_bits+i], win[:-1]))
                m.d.comb += res[i].eq(~dif[-1])

            m.d.comb += res[self.rapow:].eq(Cat(av[:trunk_bits], win))
            return res

        ar = Array(Signal(residue) for _ in range(depth + 1))
        dr = Array(Signal(divisor) for _ in range(depth + 1))
        zr = Signal()

        exec = Signal()

        if not self.pipelined:
            exec_bits = ceil_log2(steps) + 1
            cnt_exec = Signal(signed(exec_bits))

            with m.If(self.start):
                m.d.sync += cnt_exec.eq(-steps)
            with m.Elif(cnt_exec[-1]):
                m.d.sync += cnt_exec.eq(cnt_exec + 1)

            m.d.comb += exec.eq(cnt_exec[-1])
            m.d.comb += self.ready.eq(~exec)
        else:
            vld = Signal(steps + 1)
            m.d.sync += vld.eq(Cat(self.start, vld[:-1]))
            m.d.comb += self.ready.eq(vld[-1])

        an = Cat(self.a, C(0, residue.width - self.abits))
        dn = self.d

        for i in range(max(0, depth-1) + 1):
            m.d.sync += ar[i].eq(an)
            m.d.sync += dr[i].eq(dn)
            an = div_step(ar[i], dr[i])
            dn = dr[i]

        with m.If(self.pipelined | (~self.start & exec)):
            m.d.sync += [
                ar[-1].eq(an),
                dr[-1].eq(dn),
                zr.eq(dn == 0),
            ]

        m.d.comb += [
            self.q.eq(ar[-1][:self.abits]),
            self.r.eq(ar[-1][steps*self.rapow:][:self.dbits]),
            self.z.eq(zr),
        ]

        return m
