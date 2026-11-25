#!/usr/bin/env python3
"""Build the Beacon Holdout Click package."""
from argparse import ArgumentParser
from pathlib import Path
from shutil import copytree
from subprocess import run
from tempfile import TemporaryDirectory

project = Path(__file__).resolve().parent
parser = ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=project / "dist")
output = parser.parse_args().output.resolve()
output.mkdir(parents=True, exist_ok=True)

with TemporaryDirectory(prefix="beacon-holdout-") as temp:
    stage = Path(temp) / "app"
    copytree(project / "app", stage)
    stage.chmod(0o755)
    for path in stage.iterdir():
        path.chmod(0o644)
    run(["click", "build", str(stage)], cwd=output, check=True)

(output / "beacon-holdout.touchapps_0.1.0_all.click").chmod(0o644)
