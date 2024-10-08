from dataclasses import dataclass

import niar
from amaranth import *
from amaranth_boards.icebreaker import ICEBreakerPlatform


__all__ = ["icebreaker", "test", "cxxrtl"]


class icebreaker(ICEBreakerPlatform):
    prepare_kwargs = {"synth_opts": "-dsp -spram"}


class test:
    default_clk_frequency = 1_000_000


class cxxrtl(niar.CxxrtlPlatform):
    default_clk_frequency = 12_000_000.0
    uses_zig = True

    @dataclass
    class Uart:
        @dataclass
        class Pin:
            i: Signal = None
            o: Signal = None

        rx: Pin
        tx: Pin
