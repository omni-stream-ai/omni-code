#!/usr/bin/env python3
"""Audit every native library, including plugins loaded later with dlopen."""

import os
from pathlib import Path
import re
import subprocess
import sys


def verify(bundle: Path) -> None:
    if not (bundle / "omni_code").is_file() or not (bundle / "AppRun").is_file():
        raise RuntimeError("The Linux package must contain omni_code and AppRun")
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = f"{bundle / 'lib'}:{bundle / 'usr/lib'}"
    failures = []
    checked = 0
    for binary in sorted(bundle.rglob("*")):
        if binary.is_symlink():
            try:
                target = binary.resolve(strict=True)
            except (OSError, RuntimeError):
                failures.append(f"{binary.relative_to(bundle)}: broken symbolic link")
                continue
            if not target.is_relative_to(bundle):
                failures.append(f"{binary.relative_to(bundle)}: symbolic link escapes the package")
                continue
        if not binary.is_file():
            continue
        with binary.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        checked += 1
        versions = subprocess.run(
            ["readelf", "--version-info", str(binary)],
            check=True, capture_output=True, text=True,
        ).stdout
        required = {(int(a), int(b)) for a, b in re.findall(r"\bGLIBC_(\d+)\.(\d+)\b", versions)}
        if required and max(required) > (2, 35):
            failures.append(f"{binary.relative_to(bundle)} requires GLIBC_{'.'.join(map(str, max(required)))}; baseline is 2.35")
        result = subprocess.run(
            ["ldd", str(binary)], env=env, capture_output=True, text=True,
        )
        for line in (result.stdout + result.stderr).splitlines():
            if "not found" in line or "/nix/store/" in line:
                failures.append(f"{binary.relative_to(bundle)}: {line.strip()}")
        if result.returncode and not any(
            marker in result.stdout + result.stderr
            for marker in ("not a dynamic executable", "statically linked")
        ):
            failures.append(f"ldd failed for {binary.relative_to(bundle)}: {result.stderr.strip()}")
    if failures:
        raise RuntimeError("\n".join(failures))
    print(f"Verified {checked} ELF files: no missing libraries or Nix store dependencies; glibc <= 2.35.")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1]).resolve())
    except (IndexError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Linux package verification failed: {error}", file=sys.stderr)
        sys.exit(1)
