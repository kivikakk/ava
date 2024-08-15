from amaranth.lib import enum, data


__all__ = ["Op", "Type", "AluOp", "InsnX", "InsnT", "InsnTC", "InsnAlu"]

# TODO: deduplicate entire file with basic/src/isa.zig.

class Type(enum.Enum, shape=3):
    INTEGER = 0b000
    LONG    = 0b001
    SINGLE  = 0b010
    DOUBLE  = 0b011
    STRING  = 0b100


class TypeCast(enum.Enum, shape=2):
    INTEGER = 0b00
    LONG    = 0b01
    SINGLE  = 0b10
    DOUBLE  = 0b11


class Op(enum.Enum, shape=4):
    PUSH           = 0b0001
    CAST           = 0b0010
    LET            = 0b0011
    PRINT          = 0b0100
    PRINT_COMMA    = 0b0101
    PRINT_LINEFEED = 0b0110
    ALU            = 0b0111
    PRAGMA         = 0b1110


class AluOp(enum.Enum, shape=5):
    ADD   = 0b00000
    MUL   = 0b00001
    FDIV  = 0b00010
    IDIV  = 0b00011
    SUB   = 0b00100
    # NEG = 0b00101 # XXX unimpl
    EQ    = 0b00110
    NEQ   = 0b00111
    LT    = 0b01000
    GT    = 0b01001
    LTE   = 0b01010
    GTE   = 0b01011
    AND   = 0b01100
    OR    = 0b01101
    XOR   = 0b01110


class InsnX(data.Struct):
    op: Op
    rest: 4


class InsnT(data.Struct):
    op: Op
    t: Type
    rest: 1


class InsnTC(data.Struct):
    op: Op
    tf: TypeCast
    tt: TypeCast


class InsnAlu(data.Struct):
    op: Op
    t: Type
    alu: AluOp
    rest: 4
