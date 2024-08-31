import niar

from . import rtl
from .targets import cxxrtl, icebreaker


__all__ = ["AvaSoc", "main"]


class AvaSoc(niar.Project):
    name = "avasoc"
    top = rtl.Top
    targets = [icebreaker]
    cxxrtl_targets = [cxxrtl]
    externals = ["avasoc/VexRiscv.v"]


# TODO: flash.


def main():
    AvaSoc().main()
