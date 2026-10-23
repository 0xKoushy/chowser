import importlib.util
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("coverage_gate", Path(__file__).parents[1] / "check-code-coverage.py")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


# Command orchestration fixture; it never builds or launches an application.
XCRUN_FIXTURE = r"""
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args[:3] == ['xcresulttool', 'export', 'coverage']:
    output = Path(args[args.index('--output-path') + 1])
    output.mkdir(parents=True)
    for suffix in ['CoverageReport', 'CoverageArchive']:
        (output / ('fixture.' + suffix)).touch()
elif args[:2] == ['xccov', 'merge']:
    Path(args[args.index('--outReport') + 1]).touch()
elif args[:2] == ['xccov', 'view']:
    print(json.dumps({'targets': [{'name': 'Chowser.app', 'coveredLines': 80, 'executableLines': 100}]}))
elif args[0] == 'python3':
    os.execv(sys.executable, [sys.executable, *args[1:]])
else:
    raise SystemExit('Unexpected command: ' + repr(args))
"""


class CoverageGateTests(unittest.TestCase):
    def test_cli_accepts_80_percent_and_rejects_a_rounded_up_result(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            for covered, total, exit_code in [(80, 100, 0), (79999, 100000, 1)]:
                report.write_text(json.dumps({"targets": [{"name": "Chowser.app", "coveredLines": covered,
                                                           "executableLines": total}]}))
                result = subprocess.run([sys.executable, str(SPEC.origin), str(report)], capture_output=True, text=True)
                self.assertEqual(result.returncode, exit_code, result.stderr)

    def test_uses_entire_app_target_instead_of_a_high_coverage_test_target(self):
        report = {"targets": [
            {"name": "ChowserTests.xctest", "coveredLines": 100, "executableLines": 100},
            {"name": "Chowser.app", "coveredLines": 79, "executableLines": 100},
        ]}
        self.assertEqual(GATE.coverage_counts(report, "Chowser.app"), (79, 100))

    def test_runner_uses_xcode_python_when_path_python_cannot_run(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            lab = Path(directory)
            commands = lab / "bin"
            commands.mkdir()
            delegate = lab / "xcrun_fixture.py"
            delegate.write_text(XCRUN_FIXTURE)
            stubs = {
                "xcodebuild": "exit 0",
                "python3": "echo 'incompatible ambient Python' >&2\nexit 99",
                "xcrun": f"exec {shlex.quote(sys.executable)} {shlex.quote(str(delegate))} \"$@\"",
            }
            for name, body in stubs.items():
                script = commands / name
                script.write_text("#!/bin/sh\n" + body + "\n")
                script.chmod(0o700)
            result = subprocess.run(["/bin/bash", "scripts/test-e2e.sh"], cwd=root, capture_output=True, text=True,
                                    env={**os.environ, "PATH": f"{commands}:/usr/bin:/bin",
                                         "CHOWSER_TEST_RESULTS": str(lab / "results")})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("80/100 executable lines", result.stdout)
            self.assertIn("minimum 80%: PASS", result.stdout)

    def test_missing_ambiguous_empty_and_invalid_counts_are_rejected(self):
        target = {"name": "Chowser.app", "coveredLines": 80, "executableLines": 100}
        invalid = [[], "invalid", [None], [target, target], [{**target, "executableLines": 0}],
                   [{**target, "coveredLines": 101}], [{**target, "coveredLines": True}]]
        for targets in invalid:
            with self.subTest(targets=targets), self.assertRaises(ValueError):
                GATE.coverage_counts({"targets": targets}, "Chowser.app")


if __name__ == "__main__":
    unittest.main()
