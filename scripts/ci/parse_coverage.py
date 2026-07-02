#!/usr/bin/env python3
"""Parse `xcrun xccov view --report --json` (on stdin) for the pre-push coverage gates.

Prints the app target's LINE-coverage percent over the TESTABLE code. Individual functions wrapped in a `// coverage:ignore-start` … `// coverage:ignore-end` region in their source are subtracted from their file's totals: BLOCK-level, not file-level, so a genuinely-untestable block (an RTCPeerConnection handshake, a WebSocket read loop, a StoreKit call, a SwiftUI `body`) is excluded while the tested code in the SAME file (e.g. the event-dispatch, a view's logic) keeps counting. This is the iOS stand-in for coverage.py's `# pragma: no cover` / v8's ignore comments, which xccov has no native equivalent of. Each region carries a one-line reason in the source, so every exclusion is reviewable at the code.

Flags:
  --top N                 also print the N worst-covered files to stderr.
  --max-file-uncovered N  per-file gate: exit 1 and name any file whose NON-excluded uncovered lines exceed N, so a big untested logic file can't hide behind a healthy overall percent.
  --source-root DIR       where the .swift sources live (default: PalkieTalkie).
"""

import argparse
import json
import pathlib
import sys


def _app_target(report: dict) -> dict | None:
    for t in report.get("targets", []):
        if t["name"].startswith("PalkieTalkie.app") or t["name"] == "PalkieTalkie":
            return t
    return None


def _ignore_regions(source_root: str) -> dict[str, list[tuple[int, int]]]:
    # basename -> list of [start_line, end_line] regions marked with // coverage:ignore-start / -end.
    regions: dict[str, list[tuple[int, int]]] = {}
    for p in pathlib.Path(source_root).rglob("*.swift"):
        spans, start = [], None
        for i, line in enumerate(p.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1):
            if "// coverage:ignore-start" in line:
                start = i
            elif "// coverage:ignore-end" in line and start is not None:
                spans.append((start, i))
                start = None
        if spans:
            regions[p.name] = spans
    return regions


def _effective(f: dict, regions: dict[str, list[tuple[int, int]]]) -> tuple[int, int]:
    # File exec/covered minus the functions whose declaration line falls inside an ignore region.
    spans = regions.get(f["name"], [])
    exc_e = exc_c = 0
    if spans:
        for fn in f.get("functions", []):
            ln = fn.get("lineNumber", -1)
            if any(a <= ln <= b for a, b in spans):
                exc_e += fn["executableLines"]
                exc_c += fn["coveredLines"]
    return f["executableLines"] - exc_e, f["coveredLines"] - exc_c


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=0)
    parser.add_argument("--max-file-uncovered", type=int, default=0)
    parser.add_argument("--source-root", default="PalkieTalkie")
    args = parser.parse_args()

    target = _app_target(json.load(sys.stdin))
    if target is None:
        print("NO_TARGET")
        return 1

    regions = _ignore_regions(args.source_root)
    eff = [(f["name"], *_effective(f, regions)) for f in target.get("files", [])]

    if args.max_file_uncovered > 0:
        offenders = sorted(((e - c, n) for n, e, c in eff), reverse=True)
        offenders = [(u, n) for u, n in offenders if u > args.max_file_uncovered]
        if offenders:
            print(
                f"[coverage] files over {args.max_file_uncovered} uncovered lines "
                "(add tests, or wrap a genuine hardware/view block in // coverage:ignore-start/-end):",
                file=sys.stderr,
            )
            for unc, name in offenders:
                print(f"  {unc:4d}  {name}", file=sys.stderr)
            return 1
        return 0

    total_e = sum(e for _, e, _ in eff)
    total_c = sum(c for _, _, c in eff)
    print(round(total_c / total_e * 100, 2) if total_e else 100.0)

    if args.top > 0:
        rows = sorted(((e - c, c / e if e else 1.0, n) for n, e, c in eff if e), reverse=True)
        print("uncovered  cov%   file", file=sys.stderr)
        for unc, cov, name in rows[: args.top]:
            if unc > 0:
                print(f"  {unc:4d}   {cov * 100:5.1f}%  {name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
