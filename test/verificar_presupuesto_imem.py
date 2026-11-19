#!/usr/bin/env python3
"""Verify that the representative matrix programs fit CERBERO instruction memory."""

import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMEM_BUNDLES = 2048
SOURCES = (
    ROOT / "test" / "ejemplos" / "convolucion.nv",
    ROOT / "test" / "ejemplos" / "multiplicacion.nv",
)


def main():
    if len(sys.argv) != 2:
        print(f"uso: {Path(sys.argv[0]).name} <novac>", file=sys.stderr)
        return 2

    novac = str(Path(sys.argv[1]).resolve())
    failures = 0
    with tempfile.TemporaryDirectory(prefix="nova-imem-") as temporary:
        for source in SOURCES:
            output = Path(temporary) / f"{source.stem}.nvx"
            result = subprocess.run(
                [novac, "--metricas", str(source), "-o", str(output)],
                capture_output=True,
                text=True,
                cwd=ROOT,
                check=False,
            )
            report = result.stdout + result.stderr
            match = re.search(r"bundles emitidos:\s*(\d+)", report)
            if result.returncode != 0 or match is None:
                print(f"FALLO: {source.name} no produjo métricas válidas")
                if report.strip():
                    print(report.strip())
                failures += 1
                continue

            bundles = int(match.group(1))
            if bundles > IMEM_BUNDLES:
                print(
                    f"FALLO: {source.name} usa {bundles} bundles; "
                    f"el límite es {IMEM_BUNDLES}"
                )
                failures += 1
            else:
                print(f"OK: {source.name}: {bundles}/{IMEM_BUNDLES} bundles")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
