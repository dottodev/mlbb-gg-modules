-- PrimeX shared runtime (GameGuardian Lua).
-- Loaded by the local loader; feature modules return objects built here.
-- No game offsets live in this file.

local U = {}
PX = U

U.VERSION = "0.1.0"
U.profile = { features = {} }
U.overrides = { features = {} }
U.modules = {}
U.cacheDir = nil
U.restoreStack = {}
U.restoreIndex = {}

local FLAG_BY_NAME = {
  byte = gg.TYPE_BYTE,
  word = gg.TYPE_WORD,
  dword = gg.TYPE_DWORD,
  float = gg.TYPE_FLOAT,
  double = gg.TYPE_DOUBLE,
  qword = gg.TYPE_QWORD,
}
local NAME_BY_FLAG = {}
for name, flag in pairs(FLAG_BY_NAME) do NAME_BY_FLAG[flag] = name end

function U.flag(name)
  return FLAG_BY_NAME[tostring(name or "")]
end

function U.flagName(flag)
  return NAME_BY_FLAG[flag] or "float"
end

function U.log(msg)
  pcall(gg.toast, tostring(msg), true)
end

function U.alert(msg)
  pcall(gg.alert, tostring(msg))
end

function U.hex(n)
  if type(n) ~= "number" then return "?" end
  return string.format("0x%X", math.floor(n))
end

function U.parseAddr(s)
  s = tostring(s or ""):gsub("%s", "")
  local h = s:match("^0[xX](%x+)$")
  if h then return tonumber(h, 16) end
  local d = s:match("^%d+$")
  if d then return tonumber(d) end
  return nil
end

function U.almost(a, b, eps)
  if type(a) ~= "number" or type(b) ~= "number" then return false end
  eps = eps or 0.001
  return math.abs(a - b) <= eps * math.max(1, math.abs(a), math.abs(b))
end

function U.read(addr, flags)
  local ok, res = pcall(gg.getValues, { { address = addr, flags = flags } })
  if not ok or type(res) ~= "table" or not res[1] then return nil, "read failed" end
  local v = tonumber(res[1].value)
  if v == nil then return nil, "non-numeric value" end
  return v, nil
end

function U.write(addr, flags, value)
  local s
  if flags == gg.TYPE_FLOAT then
    s = string.format("%.6f", value)
  elseif flags == gg.TYPE_DOUBLE then
    s = string.format("%.9f", value)
  else
    s = string.format("%d", math.floor(value + 0.5))
  end
  local ok, res = pcall(gg.setValues, { { address = addr, flags = flags, value = s } })
  if not ok then return false, tostring(res) end
  if res ~= true then return false, tostring(res) end
  return true, nil
end

function U.pushRestore(addr, flags, original, applied, owner)
  local key = tostring(addr)
  if U.restoreIndex[key] then
    local e = U.restoreIndex[key]
    e.flags, e.original, e.applied, e.owner = flags, original, applied, owner
    return
  end
  local e = { address = addr, flags = flags, original = original, applied = applied, owner = owner }
  U.restoreStack[#U.restoreStack + 1] = e
  U.restoreIndex[key] = e
end

function U.restoreOwner(owner)
  local keep = {}
  for i = 1, #U.restoreStack do
    local e = U.restoreStack[i]
    if e.owner == owner then
      local cur = U.read(e.address, e.flags)
      if cur and U.almost(cur, e.applied, 0.02) then
        U.write(e.address, e.flags, e.original)
      end
      U.restoreIndex[tostring(e.address)] = nil
    else
      keep[#keep + 1] = e
    end
  end
  U.restoreStack = keep
end

function U.restoreAll()
  for i = #U.restoreStack, 1, -1 do
    local e = U.restoreStack[i]
    local cur = U.read(e.address, e.flags)
    if cur and U.almost(cur, e.applied, 0.02) then
      U.write(e.address, e.flags, e.original)
    end
  end
  U.restoreStack = {}
  U.restoreIndex = {}
end

function U.cfg(id)
  local out = {}
  local p = U.profile.features and U.profile.features[id]
  local l = U.overrides.features and U.overrides.features[id]
  if type(p) == "table" then for k, v in pairs(p) do out[k] = v end end
  if type(l) == "table" then for k, v in pairs(l) do out[k] = v end end
  return out
end

function U.setLocal(id, patch)
  U.overrides.features[id] = U.overrides.features[id] or {}
  for k, v in pairs(patch) do U.overrides.features[id][k] = v end
  U.saveLocal()
end

function U.clearLocal(id)
  U.overrides.features[id] = nil
  U.saveLocal()
end

-- ---------- files ----------

function U.mkdir(dir)
  pcall(os.execute, 'mkdir -p "' .. tostring(dir) .. '" 2>/dev/null')
end

function U.readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function U.writeFile(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

function U.saveLocal()
  if not U.cacheDir or not U.json then return end
  U.mkdir(U.cacheDir)
  U.writeFile(U.cacheDir .. "/px_local.json", U.json.encode(U.overrides))
end

function U.loadLocal()
  if not U.cacheDir or not U.json then return end
  local s = U.readFile(U.cacheDir .. "/px_local.json")
  if not s then return end
  local ok, t = pcall(U.json.decode, s)
  if ok and type(t) == "table" then U.overrides = t end
end

-- ---------- JSON (subset: no surrogate pairs, null in arrays is dropped) ----------

local json = {}
U.json = json

local function jsonError(pos, msg)
  error("json: " .. msg .. " at " .. tostring(pos), 0)
end

function json.decode(s)
  local pos = 1
  local function skip()
    while true do
      local c = s:sub(pos, pos)
      if c == " " or c == "\n" or c == "\r" or c == "\t" then pos = pos + 1 else break end
    end
  end
  local parseValue

  local function parseString()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then jsonError(pos, "unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        if e == '"' or e == "\\" or e == "/" then out[#out + 1] = e; pos = pos + 2
        elseif e == "b" then out[#out + 1] = "\b"; pos = pos + 2
        elseif e == "f" then out[#out + 1] = "\f"; pos = pos + 2
        elseif e == "n" then out[#out + 1] = "\n"; pos = pos + 2
        elseif e == "r" then out[#out + 1] = "\r"; pos = pos + 2
        elseif e == "t" then out[#out + 1] = "\t"; pos = pos + 2
        elseif e == "u" then
          local n = tonumber(s:sub(pos + 2, pos + 5), 16) or 63
          pos = pos + 6
          if n < 128 then
            out[#out + 1] = string.char(n)
          elseif n < 2048 then
            out[#out + 1] = string.char(192 + math.floor(n / 64), 128 + n % 64)
          else
            out[#out + 1] = string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64)
          end
        else
          jsonError(pos, "bad escape")
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end

  local function parseNumber()
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not num or num == "" then jsonError(pos, "bad number") end
    pos = pos + #num
    return tonumber(num)
  end

  local function parseArray()
    pos = pos + 1
    local out = {}
    skip()
    if s:sub(pos, pos) == "]" then pos = pos + 1; return out end
    while true do
      out[#out + 1] = parseValue()
      skip()
      local c = s:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "]" then pos = pos + 1; break
      else jsonError(pos, "expected , or ]") end
    end
    return out
  end

  local function parseObject()
    pos = pos + 1
    local out = {}
    skip()
    if s:sub(pos, pos) == "}" then pos = pos + 1; return out end
    while true do
      skip()
      if s:sub(pos, pos) ~= '"' then jsonError(pos, "expected key") end
      local key = parseString()
      skip()
      if s:sub(pos, pos) ~= ":" then jsonError(pos, "expected :") end
      pos = pos + 1
      out[key] = parseValue()
      skip()
      local c = s:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "}" then pos = pos + 1; break
      else jsonError(pos, "expected , or }") end
    end
    return out
  end

  parseValue = function()
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then return parseObject() end
    if c == "[" then return parseArray() end
    if c == '"' then return parseString() end
    if c == "t" and s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if c == "f" and s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if c == "n" and s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
    return parseNumber()
  end

  local v = parseValue()
  skip()
  if pos <= #s then jsonError(pos, "trailing data") end
  return v
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t and n > 0
end

function json.encode(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then
    local s = v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
    return '"' .. s .. '"'
  end
  if t ~= "table" then return "null" end
  local out = {}
  if isArray(v) then
    for i = 1, #v do out[#out + 1] = json.encode(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for k, val in pairs(v) do
    if type(k) == "string" then
      out[#out + 1] = json.encode(k) .. ":" .. json.encode(val)
    end
  end
  return "{" .. table.concat(out, ",") .. "}"
end

-- ---------- features ----------

function U.newScaler(def)
  local f = {
    id = def.id,
    title = def.title,
    def = def,
    pct = def.defaultPct or 50,
    enabled = false,
    tickN = 0,
  }

  function f:cfg() return U.cfg(self.id) end

  function f:resolve()
    local c = self:cfg()
    local addr = U.parseAddr(c.address)
    if not addr or addr < 0x1000 then return nil, "no address configured" end
    local flags = U.flag(c.flags or U.flagName(self.def.flags or gg.TYPE_FLOAT))
    if not flags then return nil, "unknown type: " .. tostring(c.flags) end
    local cur = U.read(addr, flags)
    if not cur then return nil, "address not readable" end
    if cur < (self.def.min or -1e12) or cur > (self.def.max or 1e12) then
      return nil, string.format("value %.3f outside %.3f..%.3f", cur, self.def.min or 0, self.def.max or 0)
    end
    return { address = addr, flags = flags, base = tonumber(c.base) or cur, current = cur }
  end

  function f:ready()
    local r, err = self:resolve()
    if not r then return false, err end
    if self.def.requiresCalibration and self:cfg().calibrated ~= true then
      return false, "calibration not verified"
    end
    return true
  end

  function f:mult()
    return 1 + ((self.def.maxMult or 1.6) - 1) * (self.pct / 100)
  end

  function f:apply(r)
    local target = r.base * self:mult()
    if self.def.maxValue and target > self.def.maxValue then target = self.def.maxValue end
    if self.def.minValue and target < self.def.minValue then target = self.def.minValue end
    if r.flags ~= gg.TYPE_FLOAT and r.flags ~= gg.TYPE_DOUBLE then
      target = math.floor(target + 0.5)
    end
    local ok, err = U.write(r.address, r.flags, target)
    if not ok then return false, err end
    self.applied = target
    return true
  end

  function f:enable()
    local r, err = self:resolve()
    if not r then return false, err end
    if self.def.requiresCalibration and self:cfg().calibrated ~= true then
      return false, "calibration not verified"
    end
    self.address, self.flags, self.base = r.address, r.flags, r.base
    local ok, werr = self:apply(r)
    if not ok then return false, werr end
    self.enabled = true
    U.pushRestore(r.address, r.flags, r.current, self.applied, self.id)
    U.log(self.title .. ": on")
    return true
  end

  function f:disable()
    if not self.enabled then return end
    self.enabled = false
    U.restoreOwner(self.id)
    U.log(self.title .. ": off")
  end

  function f:tick()
    if not self.enabled then return end
    self.tickN = self.tickN + 1
    if self.tickN % 3 ~= 0 then return end
    local cur = U.read(self.address, self.flags)
    if not cur then return end
    if U.almost(cur, self.applied, 0.02) then return end
    if cur < (self.def.min or -1e12) or cur > (self.def.max or 1e12) then return end
    self.base = cur
    self:apply({ address = self.address, flags = self.flags, base = cur })
  end

  function f:status()
    local ok, reason = self:ready()
    if self.enabled then
      if self.def.maxMult and self.def.maxMult <= 1.2 then
        return string.format("ON +%.1f%%", (self:mult() - 1) * 100)
      end
      return string.format("ON %d%%", self.pct)
    end
    if ok then return string.format("OFF %d%%", self.pct) end
    return "LOCKED: " .. tostring(reason)
  end

  function f:configure()
    local c = self:cfg()
    local r = gg.prompt(
      { "Address (hex, e.g. 0x7A12345678)", "Base value (blank = read on enable)", "Type: float/dword/word/byte" },
      { tostring(c.address or ""), c.base and tostring(c.base) or "", tostring(c.flags or U.flagName(self.def.flags or gg.TYPE_FLOAT)) },
      { "string", "string", "string" }
    )
    if not r then return end
    local addr = U.parseAddr(r[1])
    local flags = U.flag(r[3])
    if not addr or addr < 0x1000 then U.alert("Invalid address"); return end
    if not flags then U.alert("Invalid type"); return end
    local base = tonumber(r[2])
    local patch = { address = string.format("0x%X", addr), flags = U.flagName(flags), base = base }
    if not base then patch.base = nil end
    U.setLocal(self.id, patch)
    local ok, err = self:ready()
    if ok then U.alert("Address saved and readable") else U.alert("Saved, but: " .. tostring(err)) end
  end

  function f:markCalibrated()
    if gg.alert("Only confirm after the calibration test: damage numbers rose AND enemy HP dropped accordingly.", "Verified", "Cancel") ~= 1 then return end
    U.setLocal(self.id, { calibrated = true })
    U.alert("Calibration marked")
  end

  return f
end

function U.newSwitch(def)
  local s = {
    id = def.id,
    title = def.title,
    def = def,
    enabled = false,
    tickN = 0,
  }

  function s:cfg() return U.cfg(self.id) end

  function s:resolve()
    local c = self:cfg()
    local addr = U.parseAddr(c.address)
    if not addr or addr < 0x1000 then return nil, "no address configured" end
    local flags = U.flag(c.flags or "byte")
    if not flags then return nil, "unknown type: " .. tostring(c.flags) end
    local on = tonumber(c.onValue)
    if not on then return nil, "no visible value configured" end
    local cur = U.read(addr, flags)
    if not cur then return nil, "address not readable" end
    return { address = addr, flags = flags, on = on, current = cur }
  end

  function s:ready()
    local r, err = self:resolve()
    if not r then return false, err end
    return true
  end

  function s:enable()
    local r, err = self:resolve()
    if not r then return false, err end
    if not U.write(r.address, r.flags, r.on) then return false, "write failed" end
    self.address, self.flags, self.on = r.address, r.flags, r.on
    self.enabled = true
    U.pushRestore(r.address, r.flags, r.current, r.on, self.id)
    U.log(self.title .. ": on")
    return true
  end

  function s:disable()
    if not self.enabled then return end
    self.enabled = false
    U.restoreOwner(self.id)
    U.log(self.title .. ": off")
  end

  function s:tick()
    if not self.enabled then return end
    self.tickN = self.tickN + 1
    if self.tickN % 4 ~= 0 then return end
    local cur = U.read(self.address, self.flags)
    if cur == nil then return end
    if not U.almost(cur, self.on, 0.001) then
      U.write(self.address, self.flags, self.on)
    end
  end

  function s:status()
    local ok, reason = self:ready()
    if self.enabled then return "ON" end
    if ok then return "OFF" end
    return "LOCKED: " .. tostring(reason)
  end

  function s:configure()
    local c = self:cfg()
    local r = gg.prompt(
      { "Address (hex)", "Visible value (number)", "Type: byte/word/dword" },
      { tostring(c.address or ""), c.onValue and tostring(c.onValue) or "1", tostring(c.flags or "byte") },
      { "string", "number", "string" }
    )
    if not r then return end
    local addr = U.parseAddr(r[1])
    local on = tonumber(r[2])
    local flags = tostring(r[3] or "byte")
    if not addr or addr < 0x1000 or not on or not U.flag(flags) then U.alert("Invalid input"); return end
    U.setLocal(self.id, { address = string.format("0x%X", addr), onValue = on, flags = flags })
    local ok, err = self:ready()
    if ok then U.alert("Saved and readable") else U.alert("Saved, but: " .. tostring(err)) end
  end

  return s
end

return U
