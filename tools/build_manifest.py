#!/usr/bin/env python3
"""Rebuild or verify manifest.json for the PrimeX GG module repo.

Checksum must match the Lua loader:
  a = (a + byte[i] * ((i % 251) + 1)) % 2**32, i is 1-based.

Usage:
  python tools/build_manifest.py            # rewrite manifest.json
  python tools/build_manifest.py --check    # verify, exit 1 on drift
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORDER = ["util", "drone", "map", "aim", "damage_phy", "damage_mag", "stealth"]
BUILD = "1211812351"


def sum32(data: bytes) -> str:
    a = 0
    for i, b in enumerate(data, start=1):
        a = (a + b * ((i % 251) + 1)) % 2**32
    return f"{a:08x}"


def modules() -> list[dict]:
    out = []
    for name in ORDER:
        path = ROOT / "modules" / f"{name}.lua"
        data = path.read_bytes()
        out.append(
            {
                "name": name,
                "file": f"modules/{name}.lua",
                "version": "0.1.0",
                "size": len(data),
                "sum": sum32(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    return out


def manifest() -> dict:
    profile = ROOT / "profiles" / f"{BUILD}.json"
    json.loads(profile.read_text(encoding="utf-8"))  # fail early on bad JSON
    return {
        "schema": 1,
        "enabled": True,
        "min_loader": 1,
        "builds": {
            BUILD: {
                "versionName": "",
                "arch": "arm64",
                "module": "libcsharp.so",
                "profile": f"profiles/{BUILD}.json",
            }
        },
        "modules": modules(),
    }


def main() -> int:
    check = "--check" in sys.argv
    path = ROOT / "manifest.json"
    text = json.dumps(manifest(), indent=2) + "\n"
    if check:
        if not path.exists():
            print("manifest.json missing")
            return 1
        if path.read_text(encoding="utf-8") != text:
            print("manifest.json is stale; run tools/build_manifest.py")
            return 1
        print("manifest.json ok")
        return 0
    path.write_text(text, encoding="utf-8")
    print(f"wrote {path} ({len(text)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
