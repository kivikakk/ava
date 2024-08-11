import subprocess
from pathlib import Path


__all__ = ["TestPlatform", "compiled", "avabasic_run_output"]


class TestPlatform:
    simulation = True
    default_clk_frequency = 1e4


def compiled(filename, basic):
    baspath = Path(__file__).parent / f".{filename}.bas"
    avcpath = Path(__file__).parent / filename
    if baspath.exists():
        if baspath.read_text() == basic:
            if avcpath.exists():
                return avcpath.read_bytes()

    compiled = subprocess.check_output(
        ["avabasic", "compile", "-"],
        input=basic.encode('utf-8'))

    avcpath.write_bytes(compiled)
    baspath.write_text(basic)

    return compiled


def avabasic_run_output(filename):
    path = Path(__file__).parent / filename
    return subprocess.check_output(["avabasic", "run", path])
