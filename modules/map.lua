-- Map reveal: forces the per-unit visibility flag that drives minimap icons.
-- Two-state write, original value captured on enable and restored on disable.
return PX.newSwitch({
  id = "map",
  title = "Map reveal",
  flags = "byte",
})
