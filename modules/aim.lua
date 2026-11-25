-- Aim assist: scales the game's own lock-on distance. No synthetic touch input.
return PX.newScaler({
  id = "aim",
  title = "Aim assist",
  flags = gg.TYPE_DWORD,
  min = 0,
  max = 100000,
  maxMult = 1.5,
  defaultPct = 40,
})
