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
from amaranth.lib.wiring import Component, In, Out
from amaranth.utils import ceil_log2


__all__ = ["Divider"]


class Divider(Component):
    def __init__(self, *, abits, dbits, rapow=1, pipelined=False):
        assert abits > 0
        assert dbits > 0
        assert rapow >= 1

        self.abits = abits
        self.dbits = dbits
        self.rapow = rapow
        self.pipelined = pipelined

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

        steps = (self.abits + self.rapow - 1) // self.rapow
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
            for i in range(self.rapow - 1, -1, -1):
                dif = (Cat(av[trunk_bits+i], win) - dv)[:self.dbits+1]
                win = Mux(~dif[self.dbits],
                    dif[:self.dbits],
                    Cat(av[trunk_bits+i], win[:self.dbits-1]))
                m.d.comb += res[i].eq(~dif[self.dbits])

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
            with m.Elif(cnt_exec[exec_bits-1]):
                m.d.sync += cnt_exec.eq(cnt_exec + 1)

            m.d.comb += exec.eq(cnt_exec[exec_bits-1])
            m.d.comb += self.ready.eq(~exec)
        else:
            vld = Signal(steps+1)
            m.d.sync += vld.eq(Cat(self.start, vld[:steps]))
            m.d.sync += self.ready.eq(vld[steps])

        an = Cat(self.a, C(0, residue.width - self.abits))
        dn = self.d

        for i in range(max(0, depth-1) + 1):
            m.d.sync += ar[i].eq(an)
            m.d.sync += dr[i].eq(dn)
            an = div_step(ar[i], dr[i])
            dn = dr[i]

        with m.If(self.pipelined | (~self.start & exec)):
            m.d.sync += [
                ar[depth].eq(an),
                dr[depth].eq(dn),
                zr.eq(dn == 0),
            ]

        m.d.comb += [
            self.q.eq(ar[depth][:self.abits]),
            self.r.eq(ar[depth][steps*self.rapow:][:self.dbits]),
            self.z.eq(zr),
        ]

        return m
