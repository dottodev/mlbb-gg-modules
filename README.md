# PrimeX MLBB — GameGuardian modules

GameGuardian Lua modules for Mobile Legends: Bang Bang. The loader stays on the
device; this repo only holds the manifest, the build profile and the feature
modules, fetched over HTTPS at runtime.

No native libraries, no injector, no external app.

## What is actually implemented

| Part | State |
|---|---|
| Loader, build gates, HTTPS fetch, size/checksum verify, cache, kill switch | implemented |
| Menu, strength sliders, per-feature toggle, restore stack, exit cleanup | implemented |
| Drone view (scales a verified camera float) | implemented, **locked** until an address is verified |
| Map reveal (forces a verified visibility flag) | implemented, **locked** |
| Aim assist (scales the game's own lock distance) | implemented, **locked** |
| Physical / magic damage (+3…8 %, calibration-gated) | implemented, **locked** |
| Stealth cleanup (GG results + saved list) | implemented |
| ESP overlay | **not possible in a pure GG script** — GG has no drawing API |

A locked feature refuses to write and says why. Nothing here ships guessed
offsets: an unverified address stays `null` and the feature stays off.

## Build identity

- Target: `com.mobile.legends`, arm64, Unity 2019.4.33f1, IL2CPP.
- Managed code lives in `libcsharp.so` (runtime-decrypted, ~104.7 MB). The
  APK's `libil2cpp.so` is a 384 KB stub; do not use its base.
- Profile key: `versionCode` `1211812351` (from the APK used for the dump).
  The loader also checks `versionName` when the profile sets one.
- Dump reference: `out_untagged2/dump.cs`. Field types are stripped in that
  dump; names and offsets are usable, types must be confirmed at runtime.

## Install

1. Copy `PrimeX.lua` to the device (any folder).
2. Open MLBB, attach GameGuardian, run the script.
3. Allow internet access when GG asks (once per run).
4. Tap the floating GG button to open the menu.

First launch needs network; later launches fall back to the cache in
`EXT_FILES_DIR/primex`.

## Calibration (the part that unlocks features)

Run `tools/discover.lua` directly in GG. It never applies a cheat.

1. **Find hero by HP** — enter the HP shown in game, take damage, enter the new
   HP. Candidates are dumped to `/sdcard/primex/dumps/<ts>/`.
2. Copy two dumps (same situation, one variable changed) to the PC and run
   `python tools/diff_dumps.py dump_a/ dump_b/`. Short changed runs are the
   candidate flags/fields.
3. **Test write with auto-revert** — write a candidate, watch the game, the tool
   restores the original after 4 s and logs the verdict to `findings.txt`.
4. Put the confirmed address into `profiles/1211812351.json` (or enter it in the
   in-game menu, which saves locally). Set `verified` to `true` only after a
   clean 3-match run.

For damage, the calibration gate is stricter: damage numbers must rise **and**
enemy HP must drop by the matching amount. If only the number moves, the stat is
display-only on this build; leave `calibrated` false.

## Repo layout

```
manifest.json              module list + hashes + build table
profiles/<build>.json      verified addresses and clamps
modules/util.lua           runtime: JSON, restore stack, scaler/switch features
modules/drone.lua
modules/map.lua
modules/aim.lua
modules/damage_phy.lua
modules/damage_mag.lua
modules/stealth.lua
tools/discover.lua         on-device discovery
tools/diff_dumps.py        offline dump diff
tools/build_manifest.py    regenerate/verify manifest
```

## Release

```bash
python tools/build_manifest.py          # rewrite manifest.json
python tools/build_manifest.py --check  # verify before push
git add -A && git commit -m "..." && git push
```

The loader only accepts a module whose byte length and checksum match the
manifest. The checksum is corruption detection, not a signature — the repo is
public and anyone can rebuild it.

## Limits

- GG's process is detectable. This repo does not claim otherwise.
- Client-side stat edits may be ignored or corrected by the server.
- Code patches are intentionally not used by default; they are the easiest thing
  for an integrity check to catch.
- Using this can get the account banned. That risk is on the operator.
