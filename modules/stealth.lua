-- Stealth cleanup: removes GG search results and the saved list, which are the
-- two local artefacts most likely to be inspected after a session.
local S = { id = "stealth", title = "Stealth cleanup" }

function S:status() return "action" end

function S:action()
  local results = 0
  local ok, n = pcall(gg.getResultsCount)
  if ok and type(n) == "number" then results = n end
  pcall(gg.clearResults)

  local items = 0
  local ok2, list = pcall(gg.getListItems)
  if ok2 and type(list) == "table" then items = #list end
  pcall(gg.clearList)

  U.alert(string.format("Cleared %d search results and %d saved-list items.", results, items))
end

return S
