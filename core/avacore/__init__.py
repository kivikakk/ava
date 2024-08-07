import niar

from . import rtl
from .targets import cxxrtl, icebreaker, ulx3s

__all__ = ["AvaCore", "main"]


class AvaCore(niar.Project):
    name = "avacore"
    top = rtl.Top
    targets = [icebreaker, ulx3s]
    cxxrtl_targets = [cxxrtl]


def main():
    AvaCore().main()
