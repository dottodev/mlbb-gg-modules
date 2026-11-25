--[[
  PrimeX discovery helper (dev tool, run directly in GameGuardian).

  It does not apply any cheat. It finds candidate addresses, dumps memory for
  offline diffing, and test-writes a value with automatic revert so a candidate
  can be confirmed without leaving the game modified.

  Output: /sdcard/primex/ (or EXT_FILES_DIR/primex)
    dumps/<timestamp>/...   raw pages around candidates
    findings.txt            one line per confirmed test write
]]

local BASE = (gg.EXT_FILES_DIR or "/sdcard") .. "/primex"
local function sh(cmd) pcall(os.execute, cmd) end
sh('mkdir -p "' .. BASE .. '/dumps"')

local function stamp()
  return os.date("%Y%m%d_%H%M%S")
end

local function parseAddr(s)
  s = tostring(s or ""):gsub("%s", "")
  local h = s:match("^0[xX](%x+)$")
  if h then return tonumber(h, 16) end
  if s:match("^%d+$") then return tonumber(s) end
  return nil
end

local function read(addr, flags)
  local r = gg.getValues({ { address = addr, flags = flags } })
  if type(r) ~= "table" or not r[1] then return nil end
  return tonumber(r[1].value)
end

local function write(addr, flags, value)
  local s
  if flags == gg.TYPE_FLOAT then s = string.format("%.6f", value)
  elseif flags == gg.TYPE_DOUBLE then s = string.format("%.9f", value)
  else s = string.format("%d", math.floor(value + 0.5)) end
  local ok, res = pcall(gg.setValues, { { address = addr, flags = flags, value = s } })
  return ok and res == true
end

local function append(line)
  local f = io.open(BASE .. "/findings.txt", "a")
  if f then f:write(line .. "\n"); f:close() end
end

local function typeMenu()
  local c = gg.choice({ "float", "dword", "word", "byte" })
  if not c then return nil end
  return ({ gg.TYPE_FLOAT, gg.TYPE_DWORD, gg.TYPE_WORD, gg.TYPE_BYTE })[c]
end

local function typeName(flags)
  if flags == gg.TYPE_FLOAT then return "float" end
  if flags == gg.TYPE_DWORD then return "dword" end
  if flags == gg.TYPE_WORD then return "word" end
  if flags == gg.TYPE_BYTE then return "byte" end
  return "?"
end

local function findHero()
  local r = gg.prompt({ "Current HP (from the game UI)" }, { "" }, { "number" })
  if not r then return end
  local hp = tonumber(r[1])
  if not hp then return end
  local flags = typeMenu()
  if not flags then return end

  gg.setRanges(gg.REGION_C_HEAP + gg.REGION_C_ALLOC + gg.REGION_C_DATA + gg.REGION_C_BSS + gg.REGION_ANONYMOUS)
  gg.clearResults()
  gg.searchNumber(tostring(hp), flags)
  local n = gg.getResultsCount()
  if n == 0 then
    gg.alert("No results. HP may be encrypted or shown rounded.")
    return
  end

  gg.alert(string.format("%d results.\nTake damage, note the new HP, then press OK.", n))
  local r2 = gg.prompt({ "New HP" }, { "" }, { "number" })
  if not r2 then return end
  local hp2 = tonumber(r2[1])
  if not hp2 then return end

  gg.refineNumber(tostring(hp2), flags)
  local n2 = gg.getResultsCount()
  if n2 == 0 then
    gg.alert("Refine emptied the list. The stat is likely encrypted or not a plain number.")
    return
  end

  local results = gg.getResults(math.min(n2, 20))
  local dir = BASE .. "/dumps/" .. stamp()
  sh('mkdir -p "' .. dir .. '"')
  local map = io.open(dir .. "/map.txt", "w")
  for i, v in ipairs(results) do
    local from = math.max(0, v.address - 0x800)
    local to = v.address + 0x800
    gg.dumpMemory(from, to, dir)
    if map then
      map:write(string.format("%d 0x%X %s\n", i, v.address, tostring(v.value)))
    end
  end
  if map then map:close() end

  gg.alert(string.format("%d candidates dumped to:\n%s\n\nCopy the folder to the PC and diff two snapshots (tools/diff_dumps.py).", n2, dir))
end

local function dumpAround()
  local r = gg.prompt({ "Address (hex)", "Radius in bytes (default 2048)" }, { "", "2048" }, { "string", "number" })
  if not r then return end
  local addr = parseAddr(r[1])
  if not addr then gg.alert("Bad address"); return end
  local radius = tonumber(r[2]) or 2048
  local dir = BASE .. "/dumps/" .. stamp()
  sh('mkdir -p "' .. dir .. '"')
  gg.dumpMemory(math.max(0, addr - radius), addr + radius, dir)
  gg.alert("Dumped to:\n" .. dir)
end

local function testWrite()
  local r = gg.prompt({ "Address (hex)", "Test value" }, { "", "" }, { "string", "string" })
  if not r then return end
  local addr = parseAddr(r[1])
  local value = tonumber(r[2])
  if not addr or not value then gg.alert("Bad input"); return end
  local flags = typeMenu()
  if not flags then return end

  local original = read(addr, flags)
  if original == nil then gg.alert("Address is not readable"); return end
  if not write(addr, flags, value) then gg.alert("Write failed"); return end

  gg.setVisible(false)
  gg.sleep(4000)
  gg.setVisible(true)
  write(addr, flags, original)

  local verdict = gg.alert(
    string.format("Address: 0x%X\nOriginal: %s\nTested: %s\n\nDid the game change as expected?", addr, tostring(original), tostring(value)),
    "Yes",
    "No"
  )
  local line = string.format(
    "%s | 0x%X | %s | original=%s | tested=%s | %s",
    stamp(), addr, typeName(flags), tostring(original), tostring(value), verdict == 1 and "CONFIRMED" or "rejected"
  )
  append(line)
  gg.alert("Logged:\n" .. line)
end

local function buildInfo()
  local i = gg.getTargetInfo()
  if type(i) ~= "table" then gg.alert("No target selected"); return end
  local ranges = gg.getRangesList("libcsharp")
  local base = "not mapped"
  if type(ranges) == "table" and ranges[1] then
    base = string.format("0x%X (%d MB)", ranges[1].start, math.floor((ranges[1]["end"] - ranges[1].start) / 1048576))
  end
  gg.alert(string.format(
    "Package: %s\nversionName: %s\nversionCode: %s\n64-bit: %s\nlibcsharp: %s",
    tostring(i.packageName), tostring(i.versionName), tostring(i.versionCode), tostring(i.x64), base
  ))
end

while true do
  local c = gg.choice({
    "Find hero by HP (dump candidates)",
    "Dump memory around address",
    "Test write with auto-revert",
    "Build info",
    "Exit",
  }, nil, "PrimeX discovery")

  if not c or c == 5 then break end
  if c == 1 then pcall(findHero)
  elseif c == 2 then pcall(dumpAround)
  elseif c == 3 then pcall(testWrite)
  elseif c == 4 then pcall(buildInfo) end
end
