import niar

from . import rtl
from .targets import cxxrtl, icebreaker

__all__ = ["AvaCore", "main"]


class AvaCore(niar.Project):
    name = "avacore"
    top = rtl.Top
    targets = [icebreaker]
    cxxrtl_targets = [cxxrtl]
    externals = ["avacore/VexRiscv.v"]


def main():
    AvaCore().main()
