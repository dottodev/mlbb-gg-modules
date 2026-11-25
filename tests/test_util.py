#!/usr/bin/env python3
"""Run util.lua against a mocked GameGuardian API (LuaJIT via lupa).

Checks: JSON round-trip, scaler enable/apply/restore, switch enable/restore,
calibration gate, and the re-apply path when the game overwrites a value.

  python tests/test_util.py
"""
from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent

MOCK = r"""
gg = {
  TYPE_BYTE = 1, TYPE_WORD = 2, TYPE_DWORD = 4,
  TYPE_FLOAT = 16, TYPE_DOUBLE = 32, TYPE_QWORD = 64,
  toast = function() end,
  alert = function() end,
}
mem = {}

function gg.getValues(items)
  local out = {}
  for i, it in ipairs(items) do
    local v = mem[it.address]
    if v == nil then return "unreadable" end
    out[i] = { address = it.address, flags = it.flags, value = v }
  end
  return out
end

function gg.setValues(items)
  for _, it in ipairs(items) do
    mem[it.address] = tonumber(it.value)
  end
  return true
end
"""

CHECKS = r"""
assert(type(PX) == "table", "util did not set PX")

-- JSON
local m = PX.json.decode('{"a":1,"b":[true,false,"x"],"c":{"d":1.5},"n":null}')
assert(m.a == 1, "json number")
assert(m.b[1] == true, "json bool")
assert(m.b[2] == false, "json false")
assert(m.b[3] == "x", "json string")
assert(m.n == nil, "json object null")
assert(math.abs(m.c.d - 1.5) < 1e-9, "json float")
local enc = PX.json.encode({ x = 1, y = { 1, 2 } })
local back = PX.json.decode(enc)
assert(back.x == 1 and back.y[2] == 2, "json round-trip")

-- scaler
PX.profile = { features = {} }
PX.overrides = { features = {} }
mem[0x1000] = 10.0
PX.overrides.features.drone = { address = "0x1000", flags = "float" }
local f = PX.newScaler({ id = "drone", title = "Drone", flags = gg.TYPE_FLOAT, min = 0.01, max = 100, maxMult = 1.6, defaultPct = 50 })
local ok, why = f:ready()
assert(ok, "scaler ready: " .. tostring(why))
assert(f:enable(), "scaler enable")
assert(math.abs(mem[0x1000] - 13.0) < 0.01, "scaler value 10*1.3, got " .. tostring(mem[0x1000]))
f:disable()
assert(math.abs(mem[0x1000] - 10.0) < 0.001, "scaler restore")

-- game overwrites while enabled -> tick re-applies
assert(f:enable(), "scaler re-enable")
mem[0x1000] = 10.0
for _ = 1, 3 do f:tick() end
assert(math.abs(mem[0x1000] - 13.0) < 0.01, "tick re-apply, got " .. tostring(mem[0x1000]))
f:disable()

-- switch
mem[0x2000] = 0
PX.overrides.features.map = { address = "0x2000", flags = "byte", onValue = 1 }
local s = PX.newSwitch({ id = "map", title = "Map" })
assert(s:enable(), "switch enable")
assert(mem[0x2000] == 1, "switch wrote 1")
s:disable()
assert(mem[0x2000] == 0, "switch restore")

-- calibration gate
PX.overrides.features.damage_phy = { address = "0x1000", flags = "float", calibrated = false }
local d = PX.newScaler({ id = "damage_phy", title = "Dmg", flags = gg.TYPE_FLOAT, min = 0, max = 1000, maxMult = 1.08, requiresCalibration = true })
local dok, derr = d:enable()
assert(not dok and derr == "calibration not verified", "calibration gate")

-- unreadable address is rejected, not guessed
PX.overrides.features.aim = { address = "0x999000", flags = "dword" }
local a = PX.newScaler({ id = "aim", title = "Aim", flags = gg.TYPE_DWORD, min = 0, max = 100000, maxMult = 1.5 })
local aok, aerr = a:ready()
assert(not aok and aerr == "address not readable", "unreadable rejected")

print("ALL TESTS PASS")
"""


def main() -> int:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    util = (ROOT / "modules" / "util.lua").read_text(encoding="utf-8")
    lua.execute(util)
    lua.execute(CHECKS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
