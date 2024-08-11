import subprocess
from pathlib import Path


__all__ = ["TestPlatform", "compiled", "avabasic_run_output"]


class TestPlatform:
    simulation = True
    default_clk_frequency = 8.0


def compiled(filename, basic):
    path = Path(__file__).parent / filename
    if path.exists():
        with open(path, "rb") as f:
            return f.read()

    compiled = subprocess.check_output(
        ["avabasic", "compile", "-"],
        input=basic.encode('utf-8'))
    with open(path, "wb") as f:
        f.write(compiled)
    return compiled


def avabasic_run_output(filename):
    path = Path(__file__).parent / filename
    return subprocess.check_output(["avabasic", "run", path])
