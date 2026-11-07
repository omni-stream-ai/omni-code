#!/usr/bin/env python3
"""List application libraries that linuxdeploy's default exclusions left on the host."""

import os
from pathlib import Path
import re
import subprocess
import sys

# Keep the host ABI and graphics dispatch/driver stack together. In particular,
# bundling an older libstdc++ can prevent a newer host Mesa driver from loading.
PLATFORM_LIBRARIES = re.compile(
    r"^(?:ld-linux.*|ld64[.]so.*|"
    r"lib(?:c|m|mvec|dl|pthread|rt|resolv|util|anl)[.]so[.].*|"
    r"libnss_.*|libgcc_s[.]so[.].*|libstdc[+][+][.]so[.].*|"
    r"lib(?:GL|EGL|GLESv1_CM|GLESv2|OpenGL|GLX|GLdispatch|glapi|gbm|vulkan)[.]so[.].*|"
    r"lib(?:GLX|EGL)_.*|libdrm(?:_.*)?[.]so[.].*)$"
)
DEPENDENCY = re.compile(r"^\s*(\S+)\s+=>\s+(/.+?)\s+\(")


def host_libraries(bundle: Path) -> list[Path]:
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    env["LD_LIBRARY_PATH"] = f"{bundle / 'lib'}:{bundle / 'usr/lib'}"
    libraries = set()
    for binary in bundle.rglob("*"):
        if not binary.is_file():
            continue
        with binary.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        result = subprocess.run(["ldd", str(binary)], env=env, capture_output=True, text=True)
        output = result.stdout + result.stderr
        if "not found" in output:
            raise RuntimeError(f"Cannot resolve native dependencies of {binary}:\n{output}")
        if result.returncode and not any(
            marker in output for marker in ("not a dynamic executable", "statically linked")
        ):
            raise RuntimeError(f"ldd failed for {binary}: {output}")
        for line in result.stdout.splitlines():
            match = DEPENDENCY.match(line)
            if not match or PLATFORM_LIBRARIES.fullmatch(match[1]):
                continue
            library = Path(match[2])
            if not library.resolve().is_relative_to(bundle):
                libraries.add(library)
    return sorted(libraries)


if __name__ == "__main__":
    try:
        for library in host_libraries(Path(sys.argv[1]).resolve()):
            sys.stdout.buffer.write(os.fsencode(library) + b"\0")
    except (IndexError, OSError, RuntimeError) as error:
        print(f"Linux dependency collection failed: {error}", file=sys.stderr)
        sys.exit(1)
