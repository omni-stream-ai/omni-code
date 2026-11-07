import contextlib
import importlib.util
import io
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "verify_linux_bundle", Path(__file__).parents[1] / "verify-linux-bundle.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
COLLECTOR_SPEC = importlib.util.spec_from_file_location(
    "linux_host_libraries", Path(__file__).parents[1] / "linux-host-libraries.py"
)
COLLECTOR = importlib.util.module_from_spec(COLLECTOR_SPEC)
COLLECTOR_SPEC.loader.exec_module(COLLECTOR)


class VerifyLinuxBundleTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name)
        (self.bundle / "lib").mkdir()
        (self.bundle / "AppRun").write_text("#!/bin/sh\nexec ./omni_code\n")
        self.compile("main.c", "int main(void) { return 0; }", "omni_code")
        self.compile(
            "child.c", "int child(void) { return 42; }", "lib/libchild.so",
            "-shared", "-fPIC", "-Wl,-soname,libchild.so",
        )
        self.compile(
            "plugin.c", "int child(void); int plugin(void) { return child(); }",
            "lib/libplugin.so", "-shared", "-fPIC",
            f"-L{self.bundle / 'lib'}", "-lchild", "-Wl,-rpath,$ORIGIN",
        )

    def compile(self, source, content, output, *flags):
        source_path = self.bundle / source
        source_path.write_text(content)
        subprocess.run(
            ["cc", str(source_path), *flags, "-o", str(self.bundle / output)],
            check=True, capture_output=True, text=True,
        )

    def test_complete_bundle(self):
        with contextlib.redirect_stdout(io.StringIO()):
            MODULE.verify(self.bundle)

    def test_missing_dependency_of_a_dynamically_loaded_plugin(self):
        (self.bundle / "lib/libchild.so").unlink()
        with self.assertRaisesRegex(RuntimeError, r"libplugin.so.*libchild.so.*not found"):
            MODULE.verify(self.bundle)

    def test_newer_glibc_is_rejected(self):
        binary = self.bundle / "omni_code"
        content = binary.read_bytes()
        newer = re.sub(rb"GLIBC_2[.](\d+)", lambda m: b"GLIBC_9." + b"9" * len(m[1]), content)
        self.assertNotEqual(content, newer)
        binary.write_bytes(newer)
        with self.assertRaisesRegex(RuntimeError, r"baseline is 2[.]35"):
            MODULE.verify(self.bundle)

    def test_broken_plugin_link_is_rejected(self):
        (self.bundle / "lib/libbroken.so").symlink_to("missing.so")
        with self.assertRaisesRegex(RuntimeError, "broken symbolic link"):
            MODULE.verify(self.bundle)

    def test_link_to_the_build_machine_is_rejected(self):
        (self.bundle / "lib/external").symlink_to("/etc/passwd")
        with self.assertRaisesRegex(RuntimeError, "symbolic link escapes the package"):
            MODULE.verify(self.bundle)

    def test_collects_a_library_available_only_on_the_build_machine(self):
        with tempfile.TemporaryDirectory() as host_directory:
            library = Path(host_directory) / "libchild.so"
            (self.bundle / "lib/libchild.so").rename(library)
            subprocess.run(
                ["patchelf", "--set-rpath", host_directory, str(self.bundle / "lib/libplugin.so")],
                check=True,
            )
            self.assertEqual(COLLECTOR.host_libraries(self.bundle), [library])


if __name__ == "__main__":
    unittest.main()
