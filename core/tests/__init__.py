import subprocess
from pathlib import Path

__all__ = ["TestPlatform", "compiled"]


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
