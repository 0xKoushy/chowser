#!/usr/bin/env python3
"""Gate the complete application target from `xcrun xccov view --report --json`."""
import argparse
import json
import sys
from pathlib import Path


def coverage_counts(report, target):
    targets = report.get("targets", []) if isinstance(report, dict) else report
    if not isinstance(targets, list) or any(not isinstance(item, dict) for item in targets):
        raise ValueError("Expected a list of coverage targets")
    matches = [item for item in targets if item.get("name") == target]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {target} target, found {len(matches)}")
    covered = matches[0]["coveredLines"]
    total = matches[0]["executableLines"]
    if type(covered) is not int or type(total) is not int or not 0 <= covered <= total or total == 0:
        raise ValueError("Invalid or empty coverage counts")
    return covered, total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    target = "Chowser.app"
    try:
        covered, total = coverage_counts(json.loads(args.report.read_text()), target)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Coverage report rejected: {error}", file=sys.stderr)
        return 2
    passed = covered * 100 >= total * 80
    print(f"{target}: {covered}/{total} executable lines ({100 * covered / total:.2f}%), minimum 80%: {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
