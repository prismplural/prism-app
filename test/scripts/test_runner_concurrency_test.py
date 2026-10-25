"""Runner argument contracts; no Flutter, Cargo, relay, or native builds.

Run: python3 -m unittest discover -s test/scripts -p '*_test.py'
These execute the runners' real validation prologues and Flutter command lines
with a shell function recording argv. They do not qualify the native lane.
"""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ("test_fast.sh", "test_native.sh")


class RunnerConcurrencyTest(unittest.TestCase):
    def env(self, value):
        env = dict(os.environ)
        env.pop("PRISM_TEST_CONCURRENCY", None)
        if value is not None:
            env["PRISM_TEST_CONCURRENCY"] = value
        return env

    def commands(self, script):
        source = (ROOT / "scripts" / script).read_text()
        prologue = source.split("\nroot=", 1)[0]
        logical = source.replace("\\\n", " ")
        commands = re.findall(r"\b(flutter test [^\n]+)", logical, re.MULTILINE)
        self.assertEqual(len(commands), 1 if script == "test_fast.sh" else 2)
        return prologue, [re.split(r"\s+\|\s+tee\b", cmd)[0] for cmd in commands]

    def test_actual_commands_preserve_default_and_forward_override(self):
        setup = r"""
flutter() { printf '%s\n' "$@"; }
tests=('test/fast.dart')
test_paths=('test/native.dart')
native_test_args=(--exclude-tags=benchmark)
results_dir=unused
native_report=unused/native.json
"""
        for script in SCRIPTS:
            prologue, commands = self.commands(script)
            for index, command in enumerate(commands):
                for value in (None, "", "1", "2", "12"):
                    with self.subTest(script=script, command=index, value=value):
                        result = subprocess.run(
                            ["/bin/bash"], input=prologue + setup + command + "\n",
                            env=self.env(value), text=True, capture_output=True,
                            timeout=5,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        argv = result.stdout.splitlines()
                        expected = [f"--concurrency={value}"] if value else []
                        self.assertEqual([a for a in argv if a.startswith("--concurrency")], expected)
                        self.assertNotIn("", argv)
                        self.assertEqual(argv[0], "test")
                        self.assertIn("--file-reporter", argv)
                        self.assertTrue(any(a.endswith(".dart") for a in argv))
                        if script == "test_fast.sh":
                            self.assertIn("--exclude-tags=integration || slow || fixture-gen || benchmark || golden", argv)
                        elif index == 0:
                            self.assertIn("--exclude-tags=benchmark", argv)
                        else:
                            self.assertIn("--tags=benchmark", argv)

    def test_invalid_values_fail_before_any_tool_is_started(self):
        for script in SCRIPTS:
            for value in ("0", "-1", "1.5", "many", "2 3", " 2", "2\n", "$(false)"):
                with self.subTest(script=script, value=value):
                    env = self.env(value)
                    env["PATH"] = "/nonexistent-no-tools"
                    result = subprocess.run(
                        ["/bin/bash", str(ROOT / "scripts" / script)],
                        env=env, text=True, capture_output=True, timeout=5,
                    )
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(result.stderr.strip(), "PRISM_TEST_CONCURRENCY must be a positive integer.")

    def test_runner_shell_syntax(self):
        for script in SCRIPTS:
            result = subprocess.run(
                ["/bin/bash", "-n", str(ROOT / "scripts" / script)],
                text=True, capture_output=True, timeout=5,
            )
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
