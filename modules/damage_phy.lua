-- Extra physical damage: small multiplier on the live physical attack stat.
-- Locked until the calibration test proves the change reaches enemy HP.
return PX.newScaler({
  id = "damage_phy",
  title = "Physical damage",
  flags = gg.TYPE_FLOAT,
  min = 0,
  max = 100000,
  maxMult = 1.08,
  defaultPct = 50,
  requiresCalibration = true,
})
