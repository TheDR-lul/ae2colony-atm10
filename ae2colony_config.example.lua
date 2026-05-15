-- Rename to ae2colony_config.lua on the computer (same folder as ae2Colony.lua).
-- Must return a table. Keys you omit keep script defaults.

return {
  exportSide = "top",
  exportChestPeripheral = nil,
  exportLedgerFile = "ae2colony_export_ledger.json",
  scanInterval = 30,
  colonyUiInterval = 5,
  showConstructionDetail = true,
  showBuildingsList = false,
  buildingsBreakerMinutes = 30,
  maxLinesPerGroup = 12,
  monitorGroupOrder = {
    "COLONY",
    "WARN",
    "ERROR",
    "MISSING",
    "CRAFT",
    "SENT",
    "MANUAL",
    "INFO",
  },
  craftMaxStack = false,
  doLog = false,
  doLogExtra = false,
  -- missingPatternHook = { enabled = false, httpUrl = nil, httpSecret = nil },
}
