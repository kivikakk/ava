import niar
from amaranth_boards.icebreaker import ICEBreakerPlatform
from amaranth_boards.ulx3s import ULX3S_45F_Platform

__all__ = ["icebreaker", "ulx3s", "cxxrtl"]


class icebreaker(ICEBreakerPlatform):
    pass


class ulx3s(ULX3S_45F_Platform):
    pass


class cxxrtl(niar.CxxrtlPlatform):
    default_clk_frequency = 3_000_000.0
    uses_zig = True
