from amaranth import Elaboratable, Module, Signal, Print, Format
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.memory import Memory

from .uart import UART
from .stack import Stack


__all__ = ["Core"]

HELLO_AVC = [
    0x01, 0x01, 0x00,
    0x20, 0x00,
    0x01, 0x02, 0x00,
    0x20, 0x01,
    0x0a, 0x00,
    0x0a, 0x01,
    0xa0,
    0x80,
    0x82,
]


class Core(Elaboratable):
    def __init__(self):
        self.plat_uart = None

    def elaborate(self, platform):
        m = Module()

        m.submodules.imem = imem = Memory(shape=8, depth=len(HELLO_AVC), init=HELLO_AVC)
        imem_rd = imem.read_port()

        m.submodules.stack = self.stack = stack = Stack(width=32, depth=4)
        m.d.sync += stack.w_stream.valid.eq(0)

        m.submodules.slots = self.slots = slots = Memory(shape=32, depth=4, init=[])
        slots_rd = slots.read_port()
        slots_wr = slots.write_port()
        m.d.sync += slots_wr.en.eq(0)

        m.submodules.uart = self.uart = uart = UART(self.plat_uart)

        pc = Signal(range(len(HELLO_AVC) + 1))
        m.d.comb += imem_rd.addr.eq(pc)

        self.done = done = Signal()

        with m.If(~done):
            m.d.sync += Print(Format("pc={:02x} i$={:02x}", pc, imem_rd.data))

        with m.FSM() as fsm:
            with m.State('init'):
                m.d.sync += pc.eq(pc + 1)
                with m.If(pc == len(HELLO_AVC)):
                    m.next = 'done'
                with m.Else():
                    m.next = 'decode'

            with m.State('done'):
                m.d.comb += done.eq(1)

            with m.State('decode'):
                m.d.sync += pc.eq(pc + 1)

                with m.Switch(imem_rd.data):
                    with m.Case(0x01): # PUSH_IMM_INTEGER
                        m.d.sync += Print(Format("{:>14s} -> PUSH_IMM_INTEGER", "decode"))
                        m.next = 'push.imm.integer'
                    with m.Case(0x20): # LET
                        m.d.sync += Print(Format("{:>14s} -> LET", "decode"))
                        m.next = 'let'
                    with m.Default():
                        m.d.sync += Print(Format("{:>14s} -> ?", "decode"))
                        m.next = 'done'

            with m.State('push.imm.integer'):
                m.d.sync += Print(Format("{:>14s} -> acc", "p.i.i"))
                m.d.sync += [
                    pc.eq(pc + 1),
                    stack.w_stream.p.eq(imem_rd.data),
                ]
                m.next = 'push.imm.integer.2'

            with m.State('push.imm.integer.2'):
                d = (imem_rd.data << 8) | stack.w_stream.p[:8]
                m.d.sync += Print(Format("{:>14s} -> store {:04x}", "p.i.i2", d))
                m.d.sync += [
                    pc.eq(pc + 1),
                    stack.w_stream.p.eq(d),
                    stack.w_stream.valid.eq(1),
                ]
                m.next = 'decode'

            with m.State('let'):
                m.d.sync += Print(Format("{:>14s} -> slot {:d}", "let", imem_rd.data))
                m.d.sync += [
                    pc.eq(pc + 1),
                ]
                m.next = 'decode'


        return m
