#!/usr/bin/env python3
"""Diff two GameGuardian memory dumps (single files or dump folders).

GG's dumpMemory writes page-aligned files. Compare two snapshots taken around
the same address (e.g. enemy visible vs hidden) and look for short runs of
changed bytes - those are the candidate flags/fields.

Usage:
  python tools/diff_dumps.py dump_a/ dump_b/
  python tools/diff_dumps.py before.bin after.bin
"""
import argparse
import sys
from pathlib import Path

MAX_RUNS = 400
PREVIEW = 16


def runs(a: bytes, b: bytes):
    n = min(len(a), len(b))
    i = 0
    while i < n:
        if a[i] == b[i]:
            i += 1
            continue
        start = i
        while i < n and a[i] != b[i]:
            i += 1
        yield start, a[start:i], b[start:i]


def preview(data: bytes) -> str:
    head = data[:PREVIEW]
    text = " ".join(f"{x:02x}" for x in head)
    if len(data) > PREVIEW:
        text += " ..."
    return text


def diff_files(name: str, a: bytes, b: bytes) -> int:
    print(f"\n== {name}  ({len(a)} vs {len(b)} bytes)")
    if len(a) != len(b):
        print(f"   size differs by {len(b) - len(a)} bytes")
    count = 0
    for off, old, new in runs(a, b):
        print(f"   +0x{off:06X}  len={len(new):<3} {preview(old)}  ->  {preview(new)}")
        count += 1
        if count >= MAX_RUNS:
            print("   ... output capped")
            break
    if count == 0:
        print("   identical")
    return count


def collect(path: Path) -> dict[str, bytes]:
    if path.is_file():
        return {path.name: path.read_bytes()}
    return {p.name: p.read_bytes() for p in sorted(path.iterdir()) if p.is_file() and p.suffix != ".txt"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("a", type=Path)
    ap.add_argument("b", type=Path)
    args = ap.parse_args()

    for p in (args.a, args.b):
        if not p.exists():
            print(f"missing: {p}", file=sys.stderr)
            return 2

    da, db = collect(args.a), collect(args.b)
    common = sorted(set(da) & set(db))
    if not common:
        print("no common dump files (names differ; copy the folders as-is)", file=sys.stderr)
        return 2

    total = 0
    for name in common:
        total += diff_files(name, da[name], db[name])
    print(f"\n{total} differing run(s) across {len(common)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
