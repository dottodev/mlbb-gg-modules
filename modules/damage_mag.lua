-- Extra magic damage: small multiplier on the live magic power stat.
-- Locked until the calibration test proves the change reaches enemy HP.
return PX.newScaler({
  id = "damage_mag",
  title = "Magic damage",
  flags = gg.TYPE_FLOAT,
  min = 0,
  max = 100000,
  maxMult = 1.08,
  defaultPct = 50,
  requiresCalibration = true,
})
