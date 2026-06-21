#!/usr/bin/env python3
"""Parse `xcrun xccov view --report --json` output (on stdin) for the pre-push coverage gate.

Prints the PalkieTalkie app target's line-coverage percentage to stdout (one number, e.g. `89.79`) so the shell can capture and gate on it. With `--top N`, also prints the N files with the most uncovered lines to stderr — the actionable "test these first" list shown when the gate fails, so you don't re-run a 2-minute coverage build to find where the gap is.

Lives as a .py file (not a heredoc inside the shell hook) so the Python is editable and lintable on its own.
"""

import argparse
import json
import sys


def _app_target(report: dict) -> dict | None:
    for t in report.get("targets", []):
        if t["name"].startswith("PalkieTalkie.app") or t["name"] == "PalkieTalkie":
            return t
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=0, help="print N worst-covered files to stderr")
    args = parser.parse_args()

    report = json.load(sys.stdin)
    target = _app_target(report)
    if target is None:
        print("NO_TARGET")
        return 1

    print(round(target["lineCoverage"] * 100, 2))

    if args.top > 0:
        rows = []
        for f in target.get("files", []):
            uncovered = f["executableLines"] - f["coveredLines"]
            if uncovered > 0:
                rows.append((uncovered, f["lineCoverage"], f["name"]))
        rows.sort(reverse=True)
        print("uncovered  cov%   file", file=sys.stderr)
        for uncovered, cov, name in rows[: args.top]:
            print(f"  {uncovered:4d}   {cov * 100:5.1f}%  {name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
