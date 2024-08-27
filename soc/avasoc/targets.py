from dataclasses import dataclass

import niar
from amaranth import *
from amaranth_boards.icebreaker import ICEBreakerPlatform


__all__ = ["icebreaker", "cxxrtl"]


class icebreaker(ICEBreakerPlatform):
    pass


class cxxrtl(niar.CxxrtlPlatform):
    default_clk_frequency = 3_000_000.0
    uses_zig = True

    @dataclass
    class Uart:
        @dataclass
        class Pin:
            i: Signal = None
            o: Signal = None

        rx: Pin
        tx: Pin
