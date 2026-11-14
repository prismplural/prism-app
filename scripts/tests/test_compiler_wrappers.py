"""Behavioural tests for the macOS compiler wrappers (macos/.ccache-clang{,++}).

The wrappers are executed as real shell scripts with a controlled PATH: stub
`xcrun`, `ccache` and compiler binaries record what they were asked to do. No
Xcode toolchain, certificate, credential or Flutter build is involved, and every
stub lives in a temporary directory.

Run: python3 -m unittest discover -s scripts/tests -p 'test_*.py'
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WRAPPERS = {
    "clang": REPO / "macos" / ".ccache-clang",
    "clang++": REPO / "macos" / ".ccache-clang++",
}

# Each stub appends one line per invocation: its name followed by its arguments,
# space separated. The compiler stub also writes its arguments one per line so
# argument boundaries (spaces, tabs) are observable.
XCrun_STUB = """#!/bin/sh
printf 'xcrun' >> __LOG__; for a in "$@"; do printf ' %s' "$a" >> __LOG__; done; printf '\\n' >> __LOG__
if [ -n "${XCRUN_FAIL_STATUS:-}" ]; then exit "$XCRUN_FAIL_STATUS"; fi
if [ -n "${XCRUN_EMPTY:-}" ]; then exit 0; fi
if [ "$1" = "--find" ]; then printf '%s\\n' "__BIN__/$2"; exit 0; fi
exit 64
"""

CCACHE_STUB = """#!/bin/sh
printf 'ccache' >> __LOG__; for a in "$@"; do printf ' %s' "$a" >> __LOG__; done; printf '\\n' >> __LOG__
if [ -n "${CCACHE_FAIL_STATUS:-}" ]; then exit "$CCACHE_FAIL_STATUS"; fi
exec "$@"
"""

COMPILER_STUB = """#!/bin/sh
printf 'compiler' >> __LOG__; for a in "$@"; do printf ' %s' "$a" >> __LOG__; done; printf '\\n' >> __LOG__
: > "__ARGS__"
for a in "$@"; do printf '%s\\n' "$a" >> "__ARGS__"; done
exit "${COMPILER_EXIT_STATUS:-0}"
"""


class WrapperHarness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="prism-compiler-wrapper-")
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.bin = Path(self.temp) / "bin"
        self.bin.mkdir()
        self.log = Path(self.temp) / "calls.log"
        self.log.touch()
        self.args = Path(self.temp) / "compiler.args"
        self.write_stub("xcrun", XCrun_STUB)
        for tool in ("clang", "clang++"):
            self.write_stub(tool, COMPILER_STUB)
        self.env = {"PATH": str(self.bin), "HOME": self.temp, "LC_ALL": "C"}

    def write_stub(self, name: str, template: str) -> Path:
        path = self.bin / name
        path.write_text(
            template.replace("__LOG__", str(self.log))
            .replace("__BIN__", str(self.bin))
            .replace("__ARGS__", str(self.args))
        )
        path.chmod(0o755)
        return path

    def add_ccache(self) -> None:
        self.write_stub("ccache", CCACHE_STUB)

    def run_wrapper(self, tool: str, *arguments: str, env: dict | None = None):
        return subprocess.run(
            [str(WRAPPERS[tool]), *arguments],
            capture_output=True,
            text=True,
            env={**self.env, **(env or {})},
        )

    def call_lines(self) -> list[str]:
        return self.log.read_text().splitlines()

    def kinds(self) -> list[str]:
        return [line.split(" ", 1)[0] for line in self.call_lines()]

    def compiler_arguments(self) -> list[str]:
        return self.args.read_text().splitlines() if self.args.exists() else []


class WrapperContractTest(WrapperHarness):
    def test_wrappers_are_executable_shell_scripts(self):
        for tool, path in WRAPPERS.items():
            self.assertTrue(path.is_file(), tool)
            self.assertTrue(os.access(path, os.X_OK), f"{tool} is not executable")
            self.assertTrue(path.read_text().startswith("#!/bin/sh"))

    def test_absent_ccache_execs_the_real_compiler_directly(self):
        for tool in ("clang", "clang++"):
            self.log.write_text("")
            result = self.run_wrapper(tool, "-c", "file.c", "-o", "file.o")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.compiler_arguments(), ["-c", "file.c", "-o", "file.o"])
            self.assertEqual(self.kinds(), ["xcrun", "compiler"], tool)
            self.assertEqual(self.call_lines()[0], f"xcrun --find {tool}")

    def test_present_ccache_delegates_and_still_compiles(self):
        self.add_ccache()
        result = self.run_wrapper("clang", "-c", "file.c")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.kinds(), ["xcrun", "ccache", "compiler"])
        self.assertEqual(self.call_lines()[1], f"ccache {self.bin}/clang -c file.c")
        self.assertEqual(self.compiler_arguments(), ["-c", "file.c"])

    def test_argument_boundaries_survive_both_paths(self):
        arguments = ("-DNAME=two words", "--flag=a b\tc", "-I/opt/my path/include", "file with space.c")
        for with_ccache in (False, True):
            if with_ccache:
                self.add_ccache()
            self.log.write_text("")
            result = self.run_wrapper("clang", *arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.compiler_arguments(), list(arguments), f"ccache={with_ccache}")

    def test_compiler_exit_status_is_preserved(self):
        for with_ccache in (False, True):
            if with_ccache:
                self.add_ccache()
            result = self.run_wrapper("clang", "-c", "file.c", env={"COMPILER_EXIT_STATUS": "9"})
            self.assertEqual(result.returncode, 9, f"ccache={with_ccache}")

    def test_both_wrappers_resolve_their_own_compiler(self):
        self.run_wrapper("clang")
        self.assertIn(f"xcrun --find clang", self.call_lines())
        self.assertNotIn(f"xcrun --find clang++", self.call_lines())
        self.log.write_text("")
        self.run_wrapper("clang++")
        self.assertIn("xcrun --find clang++", self.call_lines())


class WrapperFailureTest(WrapperHarness):
    def test_cache_failure_is_not_retried_as_a_direct_compile(self):
        self.add_ccache()
        result = self.run_wrapper("clang", "-c", "file.c", env={"CCACHE_FAIL_STATUS": "7"})
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.kinds(), ["xcrun", "ccache"])
        self.assertNotIn("compiler", self.kinds(), "a failing cache must not trigger a second compile")
        self.assertEqual(self.compiler_arguments(), [])

    def test_xcrun_failure_is_propagated_without_invoking_anything(self):
        for tool in ("clang", "clang++"):
            for with_ccache in (False, True):
                if with_ccache:
                    self.add_ccache()
                self.log.write_text("")
                result = self.run_wrapper(tool, "-c", "file.c", env={"XCRUN_FAIL_STATUS": "3"})
                self.assertEqual(result.returncode, 3, f"{tool} ccache={with_ccache}")
                self.assertEqual(self.kinds(), ["xcrun"], f"{tool} ccache={with_ccache}")

    def test_empty_xcrun_result_fails_closed(self):
        result = self.run_wrapper("clang", "-c", "file.c", env={"XCRUN_EMPTY": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("returned no compiler", result.stderr)
        self.assertEqual(self.kinds(), ["xcrun"])

    def test_missing_xcrun_fails_closed(self):
        (self.bin / "xcrun").unlink()
        result = self.run_wrapper("clang", "-c", "file.c")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.compiler_arguments(), [])


class WrapperSourceTest(unittest.TestCase):
    """Static guards: the old unconditional exec must not come back."""

    def test_no_unconditional_ccache_exec(self):
        for path in WRAPPERS.values():
            text = path.read_text()
            self.assertNotIn('exec ccache "$(xcrun', text)
            self.assertIn("command -v ccache", text)
            self.assertIn("xcrun --find", text)

    def test_podfile_still_documents_the_fallback_it_now_gets(self):
        podfile = (REPO / "macos" / "Podfile").read_text()
        self.assertIn("fall back to plain clang if ccache is not installed", podfile)

    def test_wrappers_are_wired_as_cc_and_cxx(self):
        podfile = (REPO / "macos" / "Podfile").read_text()
        self.assertIn(".ccache-clang'", podfile)
        self.assertIn(".ccache-clang++'", podfile)
