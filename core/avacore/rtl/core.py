from amaranth import *
from amaranth.lib.enum import Enum
from amaranth.lib.memory import Memory

from .imem import ImemMemory
from .printer import Printer
from .stack import Stack
from .uart import UART


__all__ = ["Core"]


class Op(Enum, shape=3):
    ADD = 0
    MULTIPLY = 1
    FDIVIDE = 2
    IDIVIDE = 3
    SUBTRACT = 4
    NEGATE = 5
    # ...


class Type(Enum, shape=3):
    INTEGER = 0
    LONG = 1
    SINGLE = 2
    DOUBLE = 3
    STRING = 4


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

        m.submodules.printer = printer = Printer()
        with m.If(printer.r_stream.valid):
            m.d.comb += uart.wr.valid.eq(1)
            m.d.comb += uart.wr.p.eq(printer.r_stream.p)
            with m.If(uart.wr.ready):
                m.d.comb += printer.r_stream.ready.eq(1)

        self.done = done = Signal()

        op = Signal(Op)
        opa = Signal(self.ITEM_SHAPE)
        opb = Signal(self.ITEM_SHAPE)
        typ = Signal(Type)

        with m.If(~done & imem.insn_stream.valid):
            m.d.sync += Print(Format("pc={:02x} i$={:02x}", imem.pc, imem.insn_stream.p))

        with m.FSM() as fsm:
            with m.State('stall'):
                m.d.sync += Print(Format("{:>14s} |> stall", "stall"))
                with m.If(imem.insn_stream.valid):
                    m.next = 'decode'

            with m.State('decode'):
                m.d.sync += Assert(imem.insn_stream.valid)
                m.d.comb += imem.insn_stream.ready.eq(1)

                with m.Switch(imem.insn_stream.p):
                    with m.Case(0x01): # PUSH_IMM_INTEGER
                        m.d.sync += Print(Format("{:>14s} |> PUSH_IMM_INTEGER", "decode"))
                        m.next = 'push.imm.integer'
                    with m.Case(0x0a): # PUSH_VARIABLE
                        m.d.sync += Print(Format("{:>14s} |> PUSH_VARIABLE", "decode"))
                        m.next = 'push.variable'
                    with m.Case(0x20): # LET
                        m.d.sync += Print(Format("{:>14s} |> LET", "decode"))
                        m.next = 'let'
                    with m.Case(0x80): # BUILTIN_PRINT
                        m.d.sync += Print(Format("{:>14s} |> BUILTIN_PRINT", "decode"))
                        m.next = 'print'
                    with m.Case(0x82): # BUILTIN_PRINT_LINEFEED
                        m.d.sync += Print(Format("{:>14s} |> BUILTIN_PRINT_LINEFEED", "decode"))
                        m.d.comb += uart_wr_p.eq(ord(b'\n'))
                        m.d.comb += uart_wr_valid.eq(1)
                        m.next = 'stall'
                    with m.Case(0xa0): # OPERATOR_ADD_INTEGER
                        m.d.sync += Print(Format("{:>14s} |> OPERATOR_ADD_INTEGER", "decode"))
                        m.d.sync += op.eq(Op.ADD)
                        m.d.sync += typ.eq(Type.INTEGER)
                        m.next = 'alu'
                    with m.Case(0xa5): # OPERATOR_MULTIPLY_INTEGER
                        m.d.sync += Print(Format("{:>14s} |> OPERATOR_MULTIPLY_INTEGER", "decode"))
                        m.d.sync += op.eq(Op.MULTIPLY)
                        m.d.sync += typ.eq(Type.INTEGER)
                        m.next = 'alu'
                    with m.Default():
                        m.d.sync += Print(Format("{:>14s} |> ?", "decode"))
                        m.next = 'done'

            with m.State('push.imm.integer'):
                with m.If(imem.insn_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> acc", "p.i.i"))
                    m.d.sync += stack.w_stream.p.eq(imem.insn_stream.p)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'push.imm.integer.2'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "p.i.i"))

            with m.State('push.imm.integer.2'):
                with m.If(imem.insn_stream.valid):
                    d = (imem.insn_stream.p << 8) | stack.w_stream.p[:8]
                    m.d.sync += Print(Format("{:>14s} |> store v{:04x}", "p.i.i2", d))
                    m.d.sync += stack.w_stream.p.eq(d)
                    m.d.sync += stack.w_stream.valid.eq(1)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'stall'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "p.i.i2"))

            with m.State('push.variable'):
                with m.If(imem.insn_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> push s{:02x}", "p.v", imem.insn_stream.p))
                    m.d.sync += slots_rd.addr.eq(imem.insn_stream.p)
                    m.d.comb += imem.insn_stream.ready.eq(1)
                    m.next = 'push.variable.2'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "p.v"))

            with m.State('push.variable.2'):
                m.d.sync += Print(Format("{:>14s} |> wait", "p.v2"))
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
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "let"))

            with m.State('print'):
                with m.If(stack.r_stream.valid):
                    m.d.comb += printer.w_stream.p.eq(stack.r_stream.p)
                    m.d.comb += printer.w_stream.valid.eq(1)
                    with m.If(printer.w_stream.ready):
                        m.d.sync += Print(Format("{:>14s} |> v{:04x}", "print", stack.r_stream.p))
                        m.d.sync += stack.r_stream.ready.eq(1)
                        m.next = 'print.wait'
                    with m.Else():
                        m.d.sync += Print(Format("{:>14s} |> stall printer", "print"))
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall stack", "print"))

            with m.State('print.wait'):
                with m.If(printer.w_stream.ready):
                    m.next = 'decode'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall printer", "print.w"))

            with m.State('alu'):
                with m.If(stack.r_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> opb <- v{:04x}", "alu", stack.r_stream.p))
                    m.d.sync += opb.eq(stack.r_stream.p)
                    m.d.sync += stack.r_stream.ready.eq(1)
                    m.next = 'alu2'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "alu"))

            with m.State('alu2'):
                m.d.sync += Print(Format("{:>14s} |> stall", "alu2"))
                m.next = 'alu3'

            with m.State('alu3'):
                with m.If(stack.r_stream.valid):
                    m.d.sync += Print(Format("{:>14s} |> opa <- v{:04x}", "alu3", stack.r_stream.p))
                    m.d.sync += opa.eq(stack.r_stream.p)
                    m.d.sync += stack.r_stream.ready.eq(1)
                    m.next = 'alu4'
                with m.Else():
                    m.d.sync += Print(Format("{:>14s} |> stall", "alu3"))

            with m.State('alu4'):
                m.d.sync += Print(Format("{:>14s} |> v{:04x} v{:04x} ({})", "alu4", opa, opb, op))
                m.d.sync += stack.w_stream.valid.eq(1)

                m.d.sync += Assert(typ == Type.INTEGER) # XXX

                lhs = opa[:16].as_signed()
                rhs = opb[:16].as_signed()

                m.next = 'decode'
                with m.Switch(op):
                    with m.Case(Op.ADD):
                        m.d.sync += stack.w_stream.p.eq(lhs + rhs)
                    with m.Case(Op.MULTIPLY):
                        m.d.sync += stack.w_stream.p.eq(lhs * rhs)
                    with m.Case(Op.FDIVIDE):
                        m.d.sync += Assert(0) # XXX
                        m.next = 'done'
                    with m.Case(Op.IDIVIDE):
                        m.d.sync += stack.w_stream.p.eq(lhs // rhs)
                    with m.Case(Op.SUBTRACT):
                        m.d.sync += stack.w_stream.p.eq(lhs - rhs)

            with m.State('done'):
                m.d.comb += done.eq(1)

        return m
