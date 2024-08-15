from amaranth import *
from amaranth.lib.enum import Enum
from amaranth.lib.memory import Memory

from .imem import ImemMemory
from .printer import PrinterInteger
from .stack import Stack
from .uart import UART
from .isa import Type, TypeCast, Op, InsnX, InsnT, InsnTC, InsnAlu, AluOp


__all__ = ["Core"]


class Core(Elaboratable):
    STACK_N = 4
    SLOT_N = 4
    ITEM_SHAPE = 32

    def __init__(self, *, code: bytes):
        self.plat_uart = None
        self.code = code

    def elaborate(self, platform):
        m = Module()

        memory = Memory(shape=8, depth=len(self.code), init=self.code)
        m.submodules.imem = imem = ImemMemory(memory=memory)

        m.submodules.stack = self.stack = stack = Stack(width=self.ITEM_SHAPE, depth=self.STACK_N)
        m.d.sync += stack.w_stream.valid.eq(0)
        m.d.sync += stack.r_stream.ready.eq(0)

        m.submodules.slots = self.slots = slots = Memory(shape=self.ITEM_SHAPE, depth=self.SLOT_N, init=[])
        slots_rd = slots.read_port()
        slots_wr = slots.write_port()
        m.d.sync += slots_wr.en.eq(0)

        m.submodules.uart = self.uart = uart = UART(self.plat_uart)
        uart_wr_valid = Signal()
        uart_wr_p = Signal(8)
        m.d.comb += uart.wr.valid.eq(uart_wr_valid)
        m.d.comb += uart.wr.p.eq(uart_wr_p)

        col = Signal(range(80))
        spaces = Signal(range(80))

        m.submodules.printer_integer = printer_integer = PrinterInteger()
        with m.If(printer_integer.r_stream.valid):
            m.d.comb += uart.wr.valid.eq(1)
            m.d.comb += uart.wr.p.eq(printer_integer.r_stream.p)
            with m.If(uart.wr.ready):
                m.d.sync += col.eq(Mux(col == 79, 0, col + 1))
                m.d.comb += printer_integer.r_stream.ready.eq(1)

        last_insn = Signal(8)
        alu_op = Signal(AluOp)
        alu_opa = Signal(self.ITEM_SHAPE)
        alu_opb = Signal(self.ITEM_SHAPE)
        self.done = done = Signal()

        with m.If(~done & imem.insn_stream.valid):
            m.d.sync += Print(Format("pc={:02x} i$={:02x}", imem.pc, imem.insn_stream.p))

        with m.FSM() as fsm:
            with m.State('stall'):
                with m.If(imem.insn_stream.valid):
                    m.next = 'decode'

            with m.State('decode'):
                m.d.sync += Assert(imem.insn_stream.valid)
                m.d.sync += last_insn.eq(imem.insn_stream.p)
                m.d.comb += imem.insn_stream.ready.eq(1)

                ix = InsnX(imem.insn_stream.p)
                it = InsnT(imem.insn_stream.p)

                with m.Switch(ix.op):
                    with m.Case(Op.PUSH):
                        with m.If(ix.rest == 0b1000):
                            m.d.sync += Print(Format("{:>14s} |> PUSH variable", "decode"))
                            m.next = 'push.variable'
                        with m.Else():
                            m.d.sync += Print(Format("{:>14s} |> PUSH {}", "decode", it.t))
                            m.d.sync += Assert(it.t == Type.INTEGER)
                            m.next = 'push.imm'
                    with m.Case(Op.CAST):
                        m.d.sync += Print(Format("{:>14s} |> CAST", "decode"))
                        m.d.sync += Assert(0) # TODO
                        m.next = 'done'
                    with m.Case(Op.LET):
                        m.d.sync += Print(Format("{:>14s} |> LET", "decode"))
                        m.next = 'let'
                    with m.Case(Op.PRINT):
                        m.d.sync += Print(Format("{:>14s} |> PRINT", "decode"))
                        m.next = 'print'
                    with m.Case(Op.PRINT_COMMA):
                        m.d.sync += Print(Format("{:>14s} |> PRINT_COMMA", "decode"))
                        with m.If(col < 13):
                            m.d.sync += spaces.eq(14 - col)
                        with m.Elif(col < 27):
                            m.d.sync += spaces.eq(28 - col)
                        with m.Elif(col < 41):
                            m.d.sync += spaces.eq(42 - col)
                        with m.Elif(col < 55):
                            m.d.sync += spaces.eq(56 - col)
                        with m.Elif(col < 69):
                            m.d.sync += spaces.eq(70 - col)
                        with m.Else():
                            m.d.sync += spaces.eq(0)
                        m.next = 'print.comma'
                    with m.Case(Op.PRINT_LINEFEED):
                        m.d.sync += Print(Format("{:>14s} |> PRINT_LINEFEED", "decode"))
                        m.d.comb += uart_wr_p.eq(ord(b'\n'))
                        m.d.comb += uart_wr_valid.eq(1)
                        m.d.sync += col.eq(0)
                        m.next = 'stall'
                    with m.Case(Op.ALU):
                        m.d.sync += Print(Format("{:>14s} |> ALU", "decode"))
                        m.next = 'alu'
                    with m.Default():
                        m.d.sync += Print(Format("{:>14s} |> ?", "decode"))
                        m.next = 'done'

            with m.State('push.imm'):
                with m.If(imem.insn_stream.valid):
                    m.d.sync += stack.w_stream.p.eq(imem.insn_stream.p)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'push.imm.2'

            with m.State('push.imm.2'):
                with m.If(imem.insn_stream.valid):
                    d = (imem.insn_stream.p << 8) | stack.w_stream.p[:8]
                    m.d.sync += Print(Format("{:>14s} |> store v{:04x}", "p.i2", d))
                    m.d.sync += stack.w_stream.p.eq(d)
                    m.d.sync += stack.w_stream.valid.eq(1)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'stall'

            with m.State('push.variable'):
                with m.If(imem.insn_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> push s{:02x}", "p.v", imem.insn_stream.p))
                    m.d.sync += slots_rd.addr.eq(imem.insn_stream.p)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'push.variable.2'

            with m.State('push.variable.2'):
                m.next = 'push.variable.3'

            with m.State('push.variable.3'):
                m.d.sync += Print(Format("{:>14s} |> v{:04x}", "p.v3", slots_rd.data))
                m.d.sync += stack.w_stream.p.eq(slots_rd.data)
                m.d.sync += stack.w_stream.valid.eq(1)
                m.next = 'decode'

            with m.State('let'):
                with m.If(stack.r_stream.valid & imem.insn_stream.valid):
                    slot = imem.insn_stream.p
                    m.d.sync += Print(Format("{:>14s} |> s{:02x} <- v{:04x}", "let", slot, stack.r_stream.p))
                    m.d.sync += [
                        slots_wr.addr.eq(slot),
                        slots_wr.data.eq(stack.r_stream.p),
                        slots_wr.en.eq(1),
                        stack.r_stream.ready.eq(1),
                    ]
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'stall'

            with m.State('print'):
                with m.If(stack.r_stream.valid):
                    m.d.comb += printer_integer.w_stream.p.eq(stack.r_stream.p)
                    m.d.comb += printer_integer.w_stream.valid.eq(1)
                    with m.If(printer_integer.w_stream.ready):
                        m.d.sync += Print(Format("{:>14s} |> v{:04x}", "print", stack.r_stream.p))
                        m.d.sync += stack.r_stream.ready.eq(1)
                        m.next = 'print.wait'

            with m.State('print.wait'):
                with m.If(printer_integer.w_stream.ready):
                    m.next = 'decode'

            with m.State('print.comma'):
                with m.If(spaces > 0):
                    m.d.comb += uart_wr_p.eq(ord(b' '))
                    m.d.comb += uart_wr_valid.eq(1)
                    with m.If(uart.wr.valid):
                        m.d.sync += spaces.eq(spaces - 1)
                        # TODO: refactor column tracking.
                        m.d.sync += col.eq(Mux(col == 79, 0, col + 1))
                with m.Else():
                    m.next = 'decode'

            with m.State('alu'):
                ia = InsnAlu(Cat(last_insn, imem.insn_stream.p))
                with m.If(imem.insn_stream.valid & stack.r_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> opb <- v{:04x}", "alu", stack.r_stream.p))
                    m.d.sync += Assert(ia.t == Type.INTEGER)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.d.sync += [
                        alu_op.eq(ia.alu),
                        alu_opb.eq(stack.r_stream.p),
                        stack.r_stream.ready.eq(1),
                    ]
                    m.next = 'alu2'

            with m.State('alu2'):
                m.next = 'alu3'

            with m.State('alu3'):
                with m.If(stack.r_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> opa <- v{:04x}", "alu3", stack.r_stream.p))
                    m.d.sync += alu_opa.eq(stack.r_stream.p)
                    m.d.sync += stack.r_stream.ready.eq(1)
                    m.next = 'alu4'

            with m.State('alu4'):
                m.d.sync += Print(Format("{:>14s} |> v{:04x} v{:04x} ({})", "alu4",
                                         alu_opa, alu_opb, alu_op))
                m.d.sync += stack.w_stream.valid.eq(1)

                lhs = alu_opa[:16].as_signed()
                rhs = alu_opb[:16].as_signed()

                m.next = 'decode'
                with m.Switch(alu_op):
                    with m.Case(AluOp.ADD):
                        m.d.sync += stack.w_stream.p.eq(lhs + rhs)
                    with m.Case(AluOp.MUL):
                        m.d.sync += stack.w_stream.p.eq(lhs * rhs)
                    with m.Case(AluOp.FDIV):
                        m.d.sync += Assert(0) # XXX
                        m.next = 'done'
                    with m.Case(AluOp.IDIV):
                        m.d.sync += stack.w_stream.p.eq(lhs // rhs)
                    with m.Case(AluOp.SUB):
                        m.d.sync += stack.w_stream.p.eq(lhs - rhs)

            with m.State('done'):
                m.d.comb += done.eq(1)

        return m
