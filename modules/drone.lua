-- Drone view: scales the camera distance/height float.
-- Address must come from a verified profile or manual calibration.
return PX.newScaler({
  id = "drone",
  title = "Drone view",
  flags = gg.TYPE_FLOAT,
  min = 0.01,
  max = 200,
  maxMult = 1.6,
  defaultPct = 50,
})
