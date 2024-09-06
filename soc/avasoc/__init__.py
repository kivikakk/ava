import logging
import os

import niar

from . import rtl
from .targets import cxxrtl, icebreaker


__all__ = ["AvaSoc", "main"]

logger = logging.getLogger("avasoc")

class AvaSoc(niar.Project):
    name = "avasoc"
    top = rtl.Top
    targets = [icebreaker]
    cxxrtl_targets = [cxxrtl]
    externals = ["avasoc/VexRiscv.v"]


@AvaSoc.command(help="flash imem ROM")
def flash(p, parser):
    def exec(args):
        offset = int(args.offset, base=0)
        cmd = ["iceprog", "-o", hex(offset), "cxxrtl/src/avacore.imem.bin"]
        logger.debug(f"executing: {" ".join(cmd)}")
        os.execvp("iceprog", cmd)

    parser.set_defaults(func=exec)
    parser.add_argument(
        "-o",
        "--offset",
        action="store",
        default='0x800000',
        type=str,
        help="start address for write; defaults to 0x0080_0000",
    )

def main():
    AvaSoc().main()
