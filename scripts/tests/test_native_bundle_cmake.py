import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[2] / "linux/cmake/native_bundle.cmake"


class NativeBundleCMakeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.build = self.root / "build"
        self.bundle = self.root / "bundle"
        self.package = self.root / "native dependencies"
        self.helper = self.package / "bin/omni-code-prepare-linux-bundle"
        self.helper.parent.mkdir(parents=True)
        self.write_program(self.helper, """
import sys
from pathlib import Path
bundle = Path(sys.argv[1])
bundle.mkdir(parents=True, exist_ok=True)
(bundle / 'prepared').touch()
""")
        self.nix = self.root / "fake-nix"
        self.write_program(self.nix, f"print({str(self.package)!r})")
        (self.root / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.13)\n'
            'project(native_bundle_test NONE)\n'
            'set(CMAKE_CXX_COMPILER "/nix/store/test/clang++")\n'
            f'include("{MODULE}")\n'
        )
        self.env = dict(os.environ)
        self.env.pop("OMNI_CODE_LINUX_BUNDLE_PREPARER", None)
        self.env.pop("LD_LIBRARY_PATH", None)

    def write_program(self, path, body):
        path.write_text(f"#!{sys.executable}\n{body}\n")
        path.chmod(0o755)

    def configure(self, env=None):
        subprocess.run(
            ["cmake", "-S", str(self.root), "-B", str(self.build),
             f"-DCMAKE_INSTALL_PREFIX={self.bundle}",
             f"-DOMNI_NIX_EXECUTABLE={self.nix}"],
            env=self.env if env is None else env,
            check=True, capture_output=True, text=True,
        )

    def install(self, *, check=True):
        return subprocess.run(
            ["cmake", "--install", str(self.build)], env=self.env,
            check=check, capture_output=True, text=True,
        )

    def test_plain_build_keeps_the_helper_after_leaving_the_shell(self):
        self.configure(dict(self.env, OMNI_CODE_LINUX_BUNDLE_PREPARER=str(self.helper)))
        self.nix.unlink()
        self.configure()
        self.install()
        self.assertTrue((self.bundle / "prepared").is_file())

    def test_fresh_plain_build_resolves_and_caches_the_nix_helper(self):
        self.configure()
        self.nix.unlink()
        self.configure()
        self.install()
        self.assertTrue((self.bundle / "prepared").is_file())

    def test_expired_cached_helper_is_resolved_again(self):
        old_helper = self.root / "old-helper"
        shutil.copy2(self.helper, old_helper)
        self.configure(dict(self.env, OMNI_CODE_LINUX_BUNDLE_PREPARER=str(old_helper)))
        old_helper.unlink()
        self.configure()
        self.install()
        self.assertTrue((self.bundle / "prepared").is_file())

    def test_installation_fails_when_native_dependencies_cannot_be_prepared(self):
        self.write_program(self.helper, "import sys; sys.exit(1)")
        self.configure()
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native runtime dependencies are incomplete", result.stderr)


if __name__ == "__main__":
    unittest.main()
