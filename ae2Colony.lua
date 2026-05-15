local scriptName = "AE2 Colony"
local scriptVersion = "0.5.1-atm10"
-- ATM10+: disable strict gate so newer Advanced Peripherals (e.g. 0.7.59b+) can run.
local strictAdvancedPeripheralsVersion = false
local apVersionsTested = {
 ["0.7.51b"] = true,
 ["0.7.55b"] = true,
 ["0.7.59b"] = true,
 ["0.7.60b"] = true,
 ["0.7.61b"] = true,
}
local requiredAP = advancedperipherals and advancedperipherals.getAPVersion()
if not requiredAP then
 error("Advanced Peripherals API missing (advancedperipherals.getAPVersion). Is the mod loaded?")
end
if strictAdvancedPeripheralsVersion then
 if not apVersionsTested[requiredAP] then
  error("Incompatible Advanced Peripherals version: " .. tostring(requiredAP))
 end
elseif not apVersionsTested[requiredAP] then
 print(string.format(
  "[INFO] Advanced Peripherals %s is not in the narrow tested list — continuing anyway (ATM10 / newer AP).",
  tostring(requiredAP)
 ))
end

--[[-------------------------------------------------------------------------------------------------------------------
author: toastonrye
https://github.com/toastonrye/ae2Colony/blob/main/README.md
Public install latest (CC:Tweaked): wget run https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua
Frozen stable v0.4.6: wget run https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/releases/ae2Colony-v0.4.6.lua
Optional config (same folder as script): ae2colony_config.lua — see ae2colony_config.example.lua on GitHub.

Setup
Please see the Github for more detailed information!

Warning
Upstream tested ATM10 v4.2 + Advanced Peripherals 0.7.51b/0.7.55b.
This fork relaxes the version check by default for current ATM10 (NeoForge) builds.

Errors
For errors please see the Github, maybe I can help..!

Credits
Chezlordgaming - Contributions to tools & armour tier logic!
Srendi - Advanced Peripherals dev, fast support for bug troubleshooting!
---------------------------------------------------------------------------------------------------------------------]]

-- [USER CONFIG] ------------------------------------------------------------------------------------------------------
-- Export direction is relative to the **ME bridge block**, not the computer.
-- Typical build: chest **on top** of the ME bridge -> use "top".
-- Other values AP accepts: "bottom", "front", "back", "left", "right", or cardinal "north","south","east","west","up","down".
-- Docs: https://docs.advanced-peripherals.de/latest/peripherals/me_bridge/#exportitem
local exportSide = "top"

-- Optional: export into a wired-modem chest/inventory by its ComputerCraft peripheral name (run the `peripherals` program).
-- Example: "minecraft:chest_0". When set, this overrides `exportSide`.
local exportChestPeripheral = nil

-- Tracks how many items we already exported for each colony request line (see exportLedgerFile).
-- This reduces double-export while MineColonies still reports the full request count.
local exportLedgerFile = "ae2colony_export_ledger.json"
local exportLedger = {}
local craftMaxStack = false -- Autocraft exact or a stack. ie 3 logs vs 64 logs.
local scanInterval = 30 -- Probably shouldn't go much lower than 20s...
local doLog = false -- Leave false unless you have issues. Kinda spammy!
local doLogExtra = false -- If true more info printed to log file.
local logFolder = "ae2Colony_logs"
local maxLogs = 10
local maxLogSize = 200*1024 -- 100 KB
local alarm = nil -- Used to update monitor for errors.

-- When AE2 has no autocraft recipe, optionally notify an out-of-game hook (HTTP) and/or append JSONL locally.
-- Full "create encoded pattern + insert into ExtendedAE Assembly Matrix" is NOT possible from Lua alone; see docs/AUTO_PATTERN_ATM10.md
local missingPatternHook = {
 enabled = false,
 httpUrl = nil, -- e.g. "http://127.0.0.1:8099/ae2colony/missing" (run pattern-hook/server.py on the MC host)
 httpSecret = nil, -- sent as header X-AE2Colony-Secret when set
 cooldownSeconds = 120, -- per item_id, reduces spam for repeating colony requests
 logFile = "ae2colony_missing_patterns.jsonl", -- always written when enabled (in addition to HTTP when httpUrl set)
}
local missingHookLastPostMs = {}

-- Colony UI (MineColonies via colony_integrator). No exact block-% from API; see docs/MONITOR-AND-COLONY-UI.md
local colonyUiInterval = 5 -- seconds between heavy colony API refreshes (header uses cached snapshot every tick)
local showConstructionDetail = true -- getWorkOrders summary (top 3)
local showBuildingsList = false -- getBuildings (risky on some MC versions; circuit breaker on error)
local buildingsBreakerMs = 30 * 60 * 1000 -- disable getBuildings after failure
local buildingsDisabledUntil = 0 -- runtime (epoch ms UTC)
local maxLinesPerGroup = 12 -- cap lines per category on monitor
-- Full material list from active work orders (getWorkOrderResources); footer tap runs one-shot export + craft.
local showConstructionNeedsList = true
local constructionNeedsMaxWorkOrders = 3
local constructionNeedsMaxItems = 14
local showConstructionPushFooter = true
local monitorGroupOrder = {
 "COLONY",
 "NEEDS",
 "WARN",
 "ERROR",
 "MISSING",
 "CRAFT",
 "SENT",
 "MANUAL",
 "INFO",
}

local function mergeUserConfig()
 if not fs.exists("ae2colony_config.lua") then
  return
 end
 local fn, err = loadfile("ae2colony_config.lua")
 if not fn then
  return
 end
 local ok, tbl = pcall(fn)
 if not ok or type(tbl) ~= "table" then
  return
 end
 if tbl.exportSide ~= nil then
  exportSide = tbl.exportSide
 end
 if tbl.exportChestPeripheral ~= nil then
  exportChestPeripheral = tbl.exportChestPeripheral
 end
 if tbl.exportLedgerFile ~= nil then
  exportLedgerFile = tbl.exportLedgerFile
 end
 if tbl.craftMaxStack ~= nil then
  craftMaxStack = tbl.craftMaxStack
 end
 if tbl.scanInterval ~= nil then
  scanInterval = tbl.scanInterval
 end
 if tbl.doLog ~= nil then
  doLog = tbl.doLog
 end
 if tbl.doLogExtra ~= nil then
  doLogExtra = tbl.doLogExtra
 end
 if tbl.logFolder ~= nil then
  logFolder = tbl.logFolder
 end
 if tbl.maxLogs ~= nil then
  maxLogs = tbl.maxLogs
 end
 if tbl.maxLogSize ~= nil then
  maxLogSize = tbl.maxLogSize
 end
 if tbl.colonyUiInterval ~= nil then
  colonyUiInterval = tonumber(tbl.colonyUiInterval) or colonyUiInterval
 end
 if tbl.showConstructionDetail ~= nil then
  showConstructionDetail = tbl.showConstructionDetail
 end
 if tbl.showBuildingsList ~= nil then
  showBuildingsList = tbl.showBuildingsList
 end
 if tbl.buildingsBreakerMinutes ~= nil then
  local m = tonumber(tbl.buildingsBreakerMinutes)
  if m and m > 0 then
   buildingsBreakerMs = m * 60 * 1000
  end
 end
 if tbl.maxLinesPerGroup ~= nil then
  maxLinesPerGroup = tonumber(tbl.maxLinesPerGroup) or maxLinesPerGroup
 end
 if type(tbl.monitorGroupOrder) == "table" then
  monitorGroupOrder = tbl.monitorGroupOrder
 end
 if tbl.showConstructionNeedsList ~= nil then
  showConstructionNeedsList = tbl.showConstructionNeedsList
 end
 if tbl.constructionNeedsMaxWorkOrders ~= nil then
  constructionNeedsMaxWorkOrders = tonumber(tbl.constructionNeedsMaxWorkOrders) or constructionNeedsMaxWorkOrders
 end
 if tbl.constructionNeedsMaxItems ~= nil then
  constructionNeedsMaxItems = tonumber(tbl.constructionNeedsMaxItems) or constructionNeedsMaxItems
 end
 if tbl.showConstructionPushFooter ~= nil then
  showConstructionPushFooter = tbl.showConstructionPushFooter
 end
 if type(tbl.missingPatternHook) == "table" then
  for mk, mv in pairs(tbl.missingPatternHook) do
   missingPatternHook[mk] = mv
  end
 end
 if type(tbl.blacklistedTags) == "table" then
  blacklistedTags = tbl.blacklistedTags
 end
 if type(tbl.whitelistItemName) == "table" then
  whitelistItemName = tbl.whitelistItemName
 end
 print("[ae2Colony] Merged ae2colony_config.lua")
end

local function prettifyItemId(id)
 if type(id) ~= "string" then
  return "?"
 end
 local _, item = id:match("^([^:]+):(.+)$")
 if not item then
  return id
 end
 local parts = {}
 for part in item:gmatch("[^_]+") do
  if #part > 0 then
   table.insert(parts, part:sub(1, 1):upper() .. part:sub(2):lower())
  end
 end
 if #parts == 0 then
  return id
 end
 return table.concat(parts, " ")
end

local function describeItemLabel(requestItem, bridgeItem, idOverride)
 local id = idOverride or (requestItem and requestItem.name) or "?"
 if bridgeItem and type(bridgeItem.displayName) == "string" and #bridgeItem.displayName > 0 then
  return bridgeItem.displayName, id
 end
 if requestItem and type(requestItem.displayName) == "string" and #requestItem.displayName > 0 then
  return requestItem.displayName, id
 end
 return prettifyItemId(id), id
end

local function formatItemAction(prefix, count, label, id, extra)
 local base = string.format("%s x%d %s (%s)", prefix, count, label, id)
 if extra and #extra > 0 then
  return base .. " " .. extra
 end
 return base
end

local function makeLedgerKey(fingerprint, name, target)
 return tostring(fingerprint or "") .. "|" .. tostring(name or "?") .. "@" .. tostring(target or "")
end

local function loadExportLedger()
 if not exportLedgerFile or #exportLedgerFile == 0 then
  return
 end
 if not fs.exists(exportLedgerFile) then
  return
 end
 local f = fs.open(exportLedgerFile, "r")
 if not f then
  return
 end
 local txt = f.readAll()
 f.close()
 if not txt or #txt == 0 then
  return
 end
 local ok, data = pcall(textutils.unserializeJSON, txt)
 if ok and type(data) == "table" then
  exportLedger = data
 end
end

local function saveExportLedger()
 if not exportLedgerFile or #exportLedgerFile == 0 then
  return
 end
 local f = fs.open(exportLedgerFile, "w")
 if not f then
  return
 end
 f.write(textutils.serializeJSON(exportLedger))
 f.close()
end

local function syncExportLedger(colonyRequests)
 if not colonyRequests then
  return
 end
 local present = {}
 for _, request in ipairs(colonyRequests) do
  if request.items and request.items[1] then
   local it = request.items[1]
   local t = request.target or request.name or ""
   local k = makeLedgerKey(it.fingerprint, it.name, t)
   present[k] = true
   local raw = request.count or 0
   local out = exportLedger[k] or 0
   if raw < out then
    exportLedger[k] = nil
   end
  end
 end
 for k, _ in pairs(exportLedger) do
  if not present[k] then
   exportLedger[k] = nil
  end
 end
end

local colonyUiSnapshot = { headerCompact = "", lines = {}, needsLines = {}, needsEntries = {} }

local function fetchColonyUiSnapshot(colony, nowMs)
 local lines = {}
 local needsLines = {}
 local needsEntries = {}
 local parts = {}
 local function pcallNum(fn)
  local ok, v = pcall(fn)
  if ok and v ~= nil then
   return true, v
  end
  return false, nil
 end
 local okN, name = pcall(function()
  return colony.getColonyName()
 end)
 if okN and name then
  table.insert(parts, tostring(name))
 end
 local okS, sites = pcall(function()
  return colony.amountOfConstructionSites()
 end)
 if okS then
  table.insert(parts, "Sites:" .. tostring(sites))
 end
 local okC, cur = pcall(function()
  return colony.amountOfCitizens()
 end)
 local okM, maxc = pcall(function()
  return colony.maxOfCitizens()
 end)
 if okC then
  if okM then
   table.insert(parts, string.format("Cit:%s/%s", tostring(cur), tostring(maxc)))
  else
   table.insert(parts, "Cit:" .. tostring(cur))
  end
 end
 local okH, happy = pcall(function()
  return colony.getHappiness()
 end)
 if okH and happy ~= nil then
  table.insert(parts, "Hap:" .. string.format("%.0f", happy))
 end
 local okA, attack = pcall(function()
  return colony.isUnderAttack()
 end)
 if okA and attack then
  table.insert(lines, "[WARN] Colony UNDER ATTACK")
 end
 if showConstructionDetail then
  local okW, wo = pcall(function()
   return colony.getWorkOrders()
  end)
  if okW and type(wo) == "table" then
   local list = {}
   for i = 1, #wo do
    list[#list + 1] = wo[i]
   end
   table.sort(list, function(a, b)
    return (tonumber(a.priority) or 0) > (tonumber(b.priority) or 0)
   end)
   local top = math.min(3, #list)
   for i = 1, top do
    local w = list[i]
    local bn = w.buildingName or w.type or "?"
    local tl = w.targetLevel
    local tlStr = tl ~= nil and tostring(tl) or "?"
    local cl = w.isClaimed and "claimed" or "open"
    local pri = w.priority
    table.insert(
     lines,
     string.format("[COLONY] WO %s ->Lv%s %s pri=%s", tostring(bn), tlStr, cl, tostring(pri))
    )
   end
   if top > 0 and list[1] and list[1].id ~= nil then
    local okR, res = pcall(function()
     return colony.getWorkOrderResources(list[1].id)
    end)
    if okR and type(res) == "table" and #res > 0 then
     local r = res[1]
     local rn = r.displayName or r.item or "?"
     table.insert(
      lines,
      string.format("[COLONY] Top need: %s x%s (%s)", tostring(rn), tostring(r.needed or "?"), tostring(r.status or "?"))
     )
    end
   end

   if showConstructionNeedsList and top > 0 then
    local needsMap = {}
    local function mergeNeedRow(woId, r)
     if type(r) ~= "table" then
      return
     end
     local name = r.item or r.name
     if type(name) ~= "string" or #name == 0 then
      return
     end
     local fp = r.fingerprint
     local key = (fp and tostring(fp)) or name
     local n = tonumber(r.needed) or tonumber(r.count) or 0
     if n < 1 then
      n = 1
     end
     local st = tostring(r.status or "?")
     local comps = r.components
     if type(comps) ~= "table" then
      comps = {}
     end
     local prev = needsMap[key]
     if prev then
      prev.needed = prev.needed + n
      if st == "DONT_HAVE" then
       prev.status = "DONT_HAVE"
      end
     else
      needsMap[key] = {
       workOrderId = woId,
       name = name,
       fingerprint = fp,
       displayName = r.displayName,
       needed = n,
       status = st,
       components = comps,
      }
     end
    end

    local woLimit = math.min(constructionNeedsMaxWorkOrders, top)
    for wi = 1, woLimit do
     local wrow = list[wi]
     if wrow and wrow.id ~= nil then
      local okRes, res = pcall(function()
       return colony.getWorkOrderResources(wrow.id)
      end)
      if okRes and type(res) == "table" then
       for ri = 1, #res do
        mergeNeedRow(wrow.id, res[ri])
       end
      end
     end
    end

    local flat = {}
    for _, row in pairs(needsMap) do
     flat[#flat + 1] = row
    end
    table.sort(flat, function(a, b)
     local sa = a.status == "DONT_HAVE" and 0 or 1
     local sb = b.status == "DONT_HAVE" and 0 or 1
     if sa ~= sb then
      return sa < sb
     end
     return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
    end)
    local cap = math.max(1, constructionNeedsMaxItems or 14)
    for i = 1, math.min(#flat, cap) do
     local row = flat[i]
     local label = row.displayName or prettifyItemId(row.name)
     local extra = row.status == "DONT_HAVE" and " !" or ""
     table.insert(
      needsLines,
      string.format("[NEEDS] %s x%d %s%s", label, row.needed, row.status, extra)
     )
     needsEntries[#needsEntries + 1] = {
      workOrderId = row.workOrderId,
      name = row.name,
      fingerprint = row.fingerprint,
      displayName = row.displayName,
      needed = row.needed,
      status = row.status,
      components = row.components,
     }
    end
    if #flat > cap then
     table.insert(needsLines, string.format("[NEEDS] ... +%d more (see log)", #flat - cap))
    end
   end
  end
 end
 if showBuildingsList and nowMs >= buildingsDisabledUntil then
  local okB, buildings = pcall(function()
   return colony.getBuildings()
  end)
  if okB and type(buildings) == "table" then
   local shown = 0
   for i = 1, #buildings do
    local b = buildings[i]
    if b and (b.built == false or b.isWorkingOn) then
     local loc = b.location or {}
     table.insert(
      lines,
      string.format(
       "[COLONY] Site:%s @%s,%s",
       tostring(b.name or "?"),
       tostring(loc.x or "?"),
       tostring(loc.z or "?")
      )
     )
     shown = shown + 1
     if shown >= 2 then
      break
     end
    end
   end
  else
   buildingsDisabledUntil = nowMs + buildingsBreakerMs
   table.insert(lines, "[WARN] getBuildings disabled (API error; see docs)")
  end
 end
 return {
  headerCompact = table.concat(parts, " | "),
  lines = lines,
  needsLines = needsLines,
  needsEntries = needsEntries,
 }
end

-- [BLACKLIST & WHITELIST LOOKUPS] ----------------------------------------------------------------------------------------------------
-- blacklistedTags: all items matching the given tags are skipped, they do not export.
local blacklistedTags = {
 ["c:foods"] = true, -- I've noticed not all foods use tags, like at all! :(
 --["c:tools"] = true,
}

-- whitelistItemName: specific item names can be whitelisted.
-- If c:foods is blacklisted, whitelist minecraft:beef so colonists can cook into steaks!
-- QUESTION: Maybe no food should be whitelisted, the resturant seems to over-request food to cook up, filling warehouse??
local whitelistItemName = {
 --["minecraft:cod"] = true,
 ["minecraft:beef"] = true,
 ["minecraft:carrot"] = true,
 ["minecraft:potato"] = true,
 ["minecolonies:apple_pie"] = true,
}

mergeUserConfig()

-- [TOOLS & ARMOUR LOOKUPS]----------------------------------------------------------------------------------------------------
-- QUESTION: It maybe better to just have colonists make tools and armour?
-- gearNameHandler() replaces '$' with gold/diamond etc.
local gearTypes = {
 chestplate = "$_chestplate",
 boots = "$_boots",
 leggings = "$_leggings",
 helmet = "$_helmet",
 sword = "$_sword",
 pickaxe = "$_pickaxe",
 axe = "$_axe",
 shovel = "$_shovel",
 hoe = "$_hoe",
 shield = "minecraft:shield",
 bow = "minecraft:bow",
}

local gearMaterials = {
 wood = "minecraft:wooden", -- I think desc refers to wood not wooden?
 leather = "minecraft:leather",
 stone = "minecraft:stone",
 chain = "minecraft:chainmail",
 iron = "minecraft:iron",
 gold = "minecraft:golden", -- I think desc refers to gold not golden?
 diamond = "minecraft:diamond",
}

-- [LOGGING] ----------------------------------------------------------------------------------------------------------
if not fs.exists(logFolder) then fs.makeDir(logFolder) end

local function getNextLogFile()
 local files = fs.list(logFolder)
 table.sort(files)

 local numbered = {}
 for _, f in ipairs(files) do
 local n = f:match("^log_(%d+)%.log$")
 if n then table.insert(numbered, tonumber(n)) end
 end

 table.sort(numbered)

 local nextIndex = (numbered[#numbered] or 0) + 1
 return string.format("%s/log_%03d.log", logFolder, nextIndex)
end

local function logLine(line)
 if not doLog then return end
 local files = fs.list(logFolder)
 table.sort(files)
 local path
 if #files > 0 then
 local latest = files[#files]
 path = logFolder .. "/" .. latest
 if fs.getSize(path) >= maxLogSize then
 path = getNextLogFile()
 end
 else
 path = getNextLogFile()
 end
 local timestamp = os.date("%H:%M:%S", os.epoch("local") / 1000)
 local f = fs.open(path, "a")
 if f then
 f.writeLine(string.format("[%s] %s", timestamp, line))
 f.close()
 end
end

local function cleanupOldLogs()
 local files = fs.list(logFolder)
 local logFiles = {}
 for _, f in ipairs(files) do
 if f:match("^log_%d+%.log$") then
 table.insert(logFiles, f)
 end
 end
 table.sort(logFiles)
 while #logFiles > maxLogs do
 fs.delete(logFolder .. "/" .. table.remove(logFiles, 1))
 end
end

-- [MONITOR] ----------------------------------------------------------------------------------------------------------
local monitorLines = {}
local monitorColonyPrefixLines = {}
local currentPage, totalPages = 1, 1
local function setupMonitor()
 local monitor = peripheral.find("monitor")
 if not monitor then return nil end
 monitor.setTextScale(0.5)
 monitor.clear()
 monitor.setCursorPos(1, 1)
 return monitor
end

local function updateMonitorGrouped(monitor)
 if not monitor then return end

 local width, height = monitor.getSize()
 local reserved = (showConstructionPushFooter and height >= 5) and 1 or 0
 local maxLines = height - 2 - reserved
 local flatLines = {}

 local colorsMap = {
 COLONY = colors.lightBlue,
 NEEDS = colors.pink,
 WARN = colors.magenta,
 CRAFT = colors.green,
 SENT = colors.lime,
 ERROR = colors.red,
 MISSING = colors.orange,
 MANUAL = colors.cyan,
 INFO = colors.yellow,
 }

 local groups = {
 ["COLONY"] = {},
 ["NEEDS"] = {},
 ["WARN"] = {},
 ["ERROR"] = {},
 ["MISSING"] = {},
 ["CRAFT"] = {},
 ["SENT"] = {},
 ["MANUAL"] = {},
 ["INFO"] = {},
 }

 local combinedLines = {}
 for _, ln in ipairs(monitorColonyPrefixLines) do
  table.insert(combinedLines, ln)
 end
 for _, ln in ipairs(monitorLines) do
  table.insert(combinedLines, ln)
 end

 for _, line in ipairs(combinedLines) do
 local placed = false
 for _, label in ipairs(monitorGroupOrder) do
  if not placed and line:find("%[" .. label .. "%]") then
   table.insert(groups[label], line)
   placed = true
   break
  end
 end
 if not placed then
  table.insert(groups["INFO"], line)
 end
 end

 for _, label in ipairs(monitorGroupOrder) do
 local entries = groups[label]
 if entries and #entries > 0 then
 table.insert(flatLines, {text = "== " .. label .. " ==", color = colors.white})
 local cap = maxLinesPerGroup or 12
 for j = 1, math.min(#entries, cap) do
 table.insert(flatLines, {text = entries[j], color = colorsMap[label] or colors.white})
 end
 if #entries > cap then
  table.insert(
   flatLines,
   {
    text = string.format("... +%d more", #entries - cap),
    color = colors.gray,
   }
  )
 end
 end
 end

 totalPages = math.ceil(#flatLines / maxLines)
 if currentPage > totalPages then currentPage = 1 end
 local startLine = (currentPage - 1) * maxLines + 1
 local endLine = math.min(startLine + maxLines - 1, #flatLines)

 for y = 3, height do
 monitor.setCursorPos(1, y)
 monitor.write(string.rep(" ", width))
 end

 local y = 3
 for i = startLine, endLine do
 monitor.setCursorPos(1, y)
 monitor.setTextColor(flatLines[i].color)
 monitor.write(flatLines[i].text:sub(1, width))
 y = y + 1
 end
end

local function drawConstructionFooter(monitor)
 if not monitor or not showConstructionPushFooter then
  return
 end
 local w, h = monitor.getSize()
 if h < 5 then
  return
 end
 monitor.setCursorPos(1, h)
 monitor.setTextColor(colors.yellow)
 local txt = ">>> CRAFT+EXPORT (NEEDS) <<<"
 if #txt > w then
  txt = "> CRAFT+EXPORT <"
 end
 monitor.write(txt .. string.rep(" ", math.max(0, w - #txt)))
end

local function refreshMonitorBody(monitor)
 updateMonitorGrouped(monitor)
 drawConstructionFooter(monitor)
end

local function logAndDisplay(msg)
 logLine(msg)
 table.insert(monitorLines, msg)
end

local function notifyMissingPatternHook(ctx)
 if not missingPatternHook.enabled then
  return
 end
 local name = ctx and ctx.name
 if not name or name == "" then
  return
 end
 local now = os.epoch("utc")
 local cdMs = (missingPatternHook.cooldownSeconds or 120) * 1000
 local last = missingHookLastPostMs[name]
 if last and (now - last) < cdMs then
  return
 end
 missingHookLastPostMs[name] = now

 local payload = {
  item_id = name,
  count = ctx.count or 1,
  fingerprint = ctx.fingerprint or "",
  target = ctx.target or "",
  display_label = ctx.display_label or "",
  ts = now,
 }
 local body = textutils.serializeJSON(payload)
 if missingPatternHook.logFile and #missingPatternHook.logFile > 0 then
  local f = fs.open(missingPatternHook.logFile, "a")
  if f then
   f.writeLine(body)
   f.close()
  end
 end
 local url = missingPatternHook.httpUrl
 if url and http and http.post then
  local headers = { ["Content-Type"] = "application/json" }
  local secret = missingPatternHook.httpSecret
  if secret and #secret > 0 then
   headers["X-AE2Colony-Secret"] = secret
  end
  local ok, err = pcall(http.post, url, body, headers)
  if not ok and doLog then
   logLine("[missingPatternHook] http.post failed: " .. tostring(err))
  end
 end
end

-- [AP PERIPHERAL SETUP] ----------------------------------------------------------------------------------------------
local function setupPeripherals()
 term.clear()
 term.setCursorPos(1, 1)

 local bridge = peripheral.find("me_bridge") or error("me_bridge missing")
 local colony = peripheral.find("colony_integrator") or error("colony_integrator missing")
 if colony and not colony.isInColony then error("colony_integrator not in a colony") end
 return bridge, colony, setupMonitor()
end

local function confirmConnection(bridge)
 if bridge.isOnline() then
 return true
 end
 return false
end

-- [UTILS] ------------------------------------------------------------------------------------------------------------
local exportBuffer = {}
local function queueExport(fingerprint, count, name, target, ledgerKey, label, idForLog, components)
 table.insert(exportBuffer, {
 name = name,
 fingerprint = fingerprint,
 count = count,
 target = target,
 ledgerKey = ledgerKey,
 label = label,
 idForLog = idForLog or name,
 components = components or {},
 })
end

local function processExportBuffer(bridge)
 local ledgerDirty = false
 for _, item in ipairs(exportBuffer) do
 local payload = {
  fingerprint = item.fingerprint,
  name = item.name,
  count = item.count,
  components = item.components or {},
 }
 local ok, result = pcall(function()
  if exportChestPeripheral and #exportChestPeripheral > 0 then
   return bridge.exportItemToPeripheral(payload, exportChestPeripheral)
  end
  return bridge.exportItem(payload, exportSide)
 end)
 local label = item.label or prettifyItemId(item.idForLog or item.name or "?")
 local id = item.idForLog or item.name or "?"
 local tgt = "> " .. tostring(item.target or "")
 if not ok or not result then
  logAndDisplay(formatItemAction("[ERROR]", item.count, label, id, tgt))
 else
  local moved = item.count
  if type(result) == "number" then
   moved = result
  elseif result == true then
   moved = item.count
  end
  if item.ledgerKey and moved > 0 then
   exportLedger[item.ledgerKey] = (exportLedger[item.ledgerKey] or 0) + moved
   ledgerDirty = true
  end
  logAndDisplay(formatItemAction("[SENT]", moved, label, id, tgt))
 end
 end
 if ledgerDirty then
  saveExportLedger()
 end
end

local function alarmInfo(result)
end

-- [HANDLERS] ---------------------------------------------------------------------------------------------------------
-- AP fingerprints are amazing. Use "/advancedperipehrals getHashItem" in-game
local function bridgeDataHandler(bridge)
 local indexFingerprint = {}
 local ok, result = pcall(function()
 return bridge.getItems()
 end)
 if ok then
 for i = 1, #result do
 if result[i].fingerprint then indexFingerprint[result[i].fingerprint] = result[i] end
 end
 else
 logAndDisplay(string.format("[ERROR] ME Bridge Issues"))
 end
 return indexFingerprint
end

local function updateHeader(monitor, bridge, tick, snapshot)
 if not monitor then return end

 local width, _ = monitor.getSize()
 local headerText = string.format("%s v%s", scriptName, scriptVersion)
 local status = confirmConnection(bridge)
 local statusText = status and "AE2 ONLINE" or "AE2 OFFLINE"
 local statusX = width - #statusText + 1

 monitor.setCursorPos(1, 1)
 monitor.setTextColor(colors.orange)
 monitor.write(string.rep(" ", width))
 monitor.setCursorPos(1, 1)
 monitor.write(headerText)

 monitor.setCursorPos(#headerText+3, 1)
 monitor.setTextColor(colors.lightBlue)
 monitor.write(string.format("Page %d of %d (right-click)", currentPage, totalPages))

 monitor.setCursorPos(statusX, 1)
 monitor.setTextColor(status and colors.lime or colors.red)
 monitor.write(statusText)

 local left = ""
 if snapshot and type(snapshot.headerCompact) == "string" then
  left = snapshot.headerCompact
 end
 if #left > math.floor(width * 0.58) then
  left = left:sub(1, math.max(0, math.floor(width * 0.58) - 1))
 end
 monitor.setCursorPos(1, 2)
 monitor.setTextColor(colors.lightGray)
 monitor.write(left)
 local used = #left
 if used < width then
  monitor.setTextColor(colors.black)
  monitor.write(string.rep(" ", width - used))
 end
 local barW = math.max(1, width - used)
 local filled = math.floor((tick / scanInterval) * barW)
 monitor.setCursorPos(used + 1, 2)
 monitor.setTextColor(status and colors.green or colors.red)
 monitor.write(string.rep("#", math.min(filled, barW)))
end

local function colonyRequestHandler(colony)
 local ok, result = pcall(function()
 return colony.getRequests()
 end)
 if ok then
 if not next(result) then
 logAndDisplay(string.format("No Colony Requests Detected"))
 return
 else
 return result
 end
 else
 -- Reported to Advanced Peripherals Github, should be fixed in newer versions.
 -- https://github.com/IntelligenceModding/AdvancedPeripherals/issues/748
 -- In v0.7.51b colony.getRequests() can fail because colonists are missing basic tools, some issue with enchantment data.
 -- Put a few basic wooden swords/hoes/shovel/pickaxe/axes in your warehouse.
 -- Also do leather armour as well, I've seen a failure from enchantment "feather falling".
 alarm = result
 local msg = string.format("[ERROR] Critical failure for colony_integrator getRequests().")
 print(msg)
 logLine(msg)
 os.sleep(1)
 end
end

-- [CHEZ GEAR TIER LOOKUP]
-- This function builds from the gearTypes and gearMaterials tables.
local function gearNameHandler(request)
 local requestName = request and request.items[1] and request.items[1].name
 if requestName == "minecraft:bow" or requestName == "minecraft:shield" then
 return requestName
 end
 local gear = string.lower(request.name or "")
 local desc = string.lower(request.desc or "")
 local maxLevel = string.match(desc, "maximal level:%s*(%w+)")
 if not maxLevel then return nil end
 local gearType = nil
 for key in pairs(gearTypes) do
 if gear:find(key) then
 gearType = gearTypes[key]
 break
 end
 end
 local gearMaterial = gearMaterials[maxLevel]
 if gearType and gearMaterial then
 local gearName = gearType:gsub("%$", gearMaterial)
 return gearName
 end
 return nil
end

-- See blacklisted tags and whitelisted items table at top of script.
-- Basically blacklist an entire tag like c:foods then whitelist food for colonists to cook, like raw beef. Or carrots/potatoes for hospitals.
local function tagHandler(requestItem)
 if requestItem and whitelistItemName[requestItem.name] then
 return true, true
 elseif requestItem.tags then
 for _, tag in pairs(requestItem.tags) do
 if type(tag) == "string" then
 for blocked in pairs(blacklistedTags) do
 if tag:find("c:foods") then
 return true, false
 end
 end
 end
 end
 end
 return false, nil
end

-- Domum Ornamentum adds the Architect's Cutter, the player has to manually craft these special blocks.
-- QUESTION: Apparently colonists can also make them?
local function domumHandler(request)
 local requestDisplayName = request.name
 local requestItem = request.items[1]
 local requestName = requestItem.name
 local requestFingerprint = requestItem.fingerprint
 local requestComponents = requestItem.components
 
 if requestName:find("domum_ornamentum") then
 local list, flip = {}, {}
 local textureData = requestComponents and requestComponents["domum_ornamentum:texture_data"]
 if textureData then
 for _, value in pairs(textureData) do
 table.insert(list, value)
 end
 for i = #list, 1, -1 do
 table.insert(flip, list[i])
 end
 end
 local blockState = requestComponents and requestComponents["minecraft:block_state"]
 if blockState then
 for _, value in pairs(blockState) do
 table.insert(flip, value)
 end
 end
 logAndDisplay(string.format("[MANUAL] %s - %s (%s)", requestDisplayName, prettifyItemId(requestName), requestName))
 for key, value in ipairs(flip) do
 logAndDisplay(string.format("[MANUAL] #%d %s", key, value))
 end
 end
end

-- QUESTION: handle prints to terminal, monitor, log, chatbox, rednet?
local function messageHandler()
 -- todo
end

-- Tries to craft by fingerprint first, if nil it tries by name. Fingerprint is the best match!
-- https://docs.advanced-peripherals.de/latest/guides/storage_system_functions/#objects
local function craftHandler(request, bridgeItem, bridge, craftAmount, itemLabel, itemIdForLog)
 local craftable = nil
 local payload = {}
 local ok, object = nil, nil
 local ri = request.items[1]
 local fingerprintRequest = ri.fingerprint
 local name = ri.name
 local maxStackSize = ri.maxStackSize
 local stackSize
 if craftAmount ~= nil then
  stackSize = craftAmount
 else
  stackSize = (craftMaxStack and maxStackSize) or request.count
 end

 if not stackSize or stackSize == 0 then
  stackSize = 1
 end
 local label, idLog = itemLabel, itemIdForLog
 if not label or not idLog then
  label, idLog = describeItemLabel(ri, bridgeItem, name)
 end
 local fingerprintBridge = nil
 if bridgeItem and bridgeItem.fingerprint then
  fingerprintBridge = bridgeItem.fingerprint
 elseif fingerprintRequest then
  fingerprintBridge = fingerprintRequest
 end
 local comps = ri.components
 if type(comps) ~= "table" then
  comps = {}
 end
 if fingerprintBridge then
 craftable = bridge.isCraftable({fingerprint = fingerprintBridge, count = stackSize, components = comps})
 payload = {fingerprint = fingerprintBridge, count = stackSize, components = comps}
 elseif name then
 craftable = bridge.isCraftable({name = name, components = comps, count = stackSize})
 payload = {name = name, count = stackSize, components = comps}
 end
 if craftable then
 ok, object = pcall(function() return bridge.craftItem(payload) end)
 if ok then
 logAndDisplay(formatItemAction("[CRAFT]", stackSize, label, idLog, ""))
 else
 logAndDisplay(formatItemAction("[ERROR] Failed craft", stackSize, label, idLog, ""))
 end
 else
  logAndDisplay(formatItemAction("[MISSING] No recipe", stackSize, label, idLog, ""))
  notifyMissingPatternHook({
   name = name,
   count = stackSize,
   fingerprint = fingerprintRequest,
   target = (request and (request.target or request.name)) or "",
   display_label = label,
  })
 end
 return object
end

local function bridgeStockCountForNeed(bridge, entry)
 local comps = entry.components or {}
 local ok, it = pcall(function()
  if entry.fingerprint then
   return bridge.getItem({
    fingerprint = entry.fingerprint,
    name = entry.name,
    count = 65536,
    components = comps,
   })
  end
  return bridge.getItem({ name = entry.name, count = 65536, components = comps })
 end)
 if ok and it and type(it.count) == "number" then
  return it.count
 end
 return 0
end

-- One-shot: export what is already in ME for NEEDS rows, then request autocraft for the remainder.
local function manualConstructionPush(bridge, colony, monitor)
 if not showConstructionNeedsList then
  logAndDisplay("[MANUAL] NEEDS list disabled (showConstructionNeedsList=false).")
  return
 end
 local nowMs = os.epoch("utc")
 local fresh = fetchColonyUiSnapshot(colony, nowMs)
 colonyUiSnapshot = fresh
 monitorColonyPrefixLines = {}
 for _, ln in ipairs(fresh.lines) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 for _, ln in ipairs(fresh.needsLines or {}) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 local entries = fresh.needsEntries
 if not entries or #entries == 0 then
  logAndDisplay("[MANUAL] No NEEDS rows (no work orders or resources list empty).")
  if monitor then
   refreshMonitorBody(monitor)
  end
  return
 end
 if not confirmConnection(bridge) then
  logAndDisplay("[MANUAL] AE2 offline; cannot craft/export.")
  return
 end
 logAndDisplay(string.format("[MANUAL] Footer push: %d material line(s)", #entries))
 for _, entry in ipairs(entries) do
  local need = math.max(1, tonumber(entry.needed) or 1)
  local label = entry.displayName or prettifyItemId(entry.name)
  local idLog = entry.name
  local stock = bridgeStockCountForNeed(bridge, entry)
  local fromStock = math.min(stock, need)
  if fromStock > 0 then
   queueExport(
    entry.fingerprint,
    fromStock,
    entry.name,
    "work-order",
    nil,
    label,
    idLog,
    entry.components
   )
  end
  local remain = need - fromStock
  if remain > 0 then
   local comps = entry.components or {}
   local fakeRi = {
    name = entry.name,
    fingerprint = entry.fingerprint,
    maxStackSize = 64,
    components = comps,
   }
   local fakeReq = { count = remain, target = "work-order", items = { fakeRi } }
   craftHandler(fakeReq, nil, bridge, remain, label, idLog)
  end
 end
 processExportBuffer(bridge)
end

local function handleMonitorTouch(monitor, bridge, colony)
 while true do
  local event, side, _, y = os.pullEvent("monitor_touch")
  if side == peripheral.getName(monitor) then
   local _, h = monitor.getSize()
   if showConstructionPushFooter and h >= 5 and y == h then
    manualConstructionPush(bridge, colony, monitor)
   else
    currentPage = currentPage + 1
    if currentPage > totalPages then
     currentPage = 1
    end
   end
   refreshMonitorBody(monitor)
  end
 end
end

-- [MAIN HANDLER] -----------------------------------------------------------------------------------------------------
-- QUESTION: Watch for craft events maybe? https://docs.advanced-peripherals.de/latest/guides/storage_system_functions/#crafting-job
-- This is the main item exporting logic, eventually your colonists should be making foods, tools, domum ornamentum blocks, etc.
-- Case 1: First check for blacklisted tags like c:foods, then if specific food items are whitelisted before skipping export.
-- Case 2: Check for tool/armour requests, lookup material and export or craft is possible. Only non-enchanted gear.
-- Case 3. Export full requested item count, or craft if AE2 pattern exists. Export next scan cycle.
-- Case 4. No items available to export or crafting pattern to make. Make a pattern or do it manually. Or have your colonists do it.
local function mainHandler(bridge, colony)
 local colonyRequests = colonyRequestHandler(colony)
 local indexFingerprint = bridgeDataHandler(bridge)
 if not colonyRequests then
 logAndDisplay(string.format("[INFO] No colony requests detected!"))
 return
 end
 syncExportLedger(colonyRequests)
 for _, request in ipairs(colonyRequests) do
 local requestItem = request.items[1]
 if requestItem then
 local requestTarget = request.target or request.name or "Unknown Target"
 local requestFingerprint = requestItem.fingerprint
 local requestName = requestItem.name
 local ledgerKey = makeLedgerKey(requestFingerprint, requestName, requestTarget)
 local rawCount = request.count or 0
 local alreadyOut = exportLedger[ledgerKey] or 0
 if rawCount < alreadyOut then
 exportLedger[ledgerKey] = nil
 alreadyOut = 0
 end
 local requestCount = math.max(0, rawCount - alreadyOut)
 local bridgeItem = indexFingerprint[requestFingerprint]
 local debugInfo = requestName or requestFingerprint
 local label, idLog = describeItemLabel(requestItem, bridgeItem, requestName)

 local isTagBlacklisted, whitelistException = tagHandler(requestItem)
 local gearName = gearNameHandler(request)

 -- [CASE 1] Skip tag c:foods by default. Eventually your colonists should farm and cook meals!
 if isTagBlacklisted then
 if doLogExtra then logLine(string.format("[CASE 1] Tag Blacklisted [%s]", debugInfo)) end
 if whitelistException then
 if requestCount <= 0 then
 if doLogExtra then logLine("[CASE 1] Skipped (export ledger already satisfied this line)") end
 else
 local bridgeCount = (bridgeItem and bridgeItem.count) or 0
 if bridgeCount >= requestCount then
 if doLogExtra then logLine("[CASE 1] Whitelist Exception - Export Full") end
 queueExport(requestFingerprint, requestCount, requestName, requestTarget, ledgerKey, label, idLog)
 else
 if doLogExtra then logLine("[CASE 1] Whitelist Exception - Craft") end
 local craftObject = craftHandler(request, bridgeItem, bridge, requestCount, label, idLog)
 end
 end
 else
 logAndDisplay(string.format("[INFO] Tag blacklist & item not whitelist. Skipping x%d %s (%s)", rawCount, label, idLog))
 end
 -- [CASE 2] Matched keyword for tool or armour, try to export the max tiered material. Only non-enchanted.
 elseif gearName then
 if requestCount <= 0 then
 if doLogExtra then logLine(string.format("[CASE 2] Skipped (export ledger) [%s]", gearName)) end
 else
 if doLogExtra then logLine(string.format("[CASE 2] Gear Lookup [%s]", gearName)) end
 local gearStock = bridge.getItem({ name = gearName, count = requestCount, components = {} })
 local gLabel, gId = describeItemLabel({ name = gearName }, gearStock, gearName)
 if gearStock and gearStock.count > 0 then
 if doLogExtra then logLine(string.format("[CASE 2] Gear In Stock: %s", gearName)) end
 queueExport(nil, requestCount, gearName, requestTarget, ledgerKey, gLabel, gId)
 else
 local simpleRequest = {
 count = requestCount,
 target = requestTarget,
 items = {
 {
 maxStackSize = requestItem.maxStackSize,
 name = gearName,
 components = {},
 },
 },
 }
 local craftObject = craftHandler(simpleRequest, nil, bridge, requestCount, gLabel, gId)
 end
 end
 -- [CASE 3] Export if items are available, or export partial and craft. Crafted items get exported next scan.
 elseif bridgeItem then
 if requestCount <= 0 then
 if doLogExtra then logLine(string.format("[CASE 3] Skipped (export ledger) [%s]", debugInfo)) end
 else
 if doLogExtra then logLine(string.format("[CASE 3] Bridge Item [%s]", debugInfo)) end
 local bridgeCount = bridgeItem.count or 0
 local countDelta = bridgeCount - requestCount
 if countDelta > 0 then
 if doLogExtra then logLine("[CASE 3] Bridge Item - Export Full") end
 queueExport(requestFingerprint, requestCount, requestName, requestTarget, ledgerKey, label, idLog)
 elseif bridgeCount > 0 then
 if doLogExtra then logLine(string.format("[CASE 3] Bridge Item - Export & Craft [%s]", debugInfo)) end
 queueExport(requestFingerprint, bridgeCount, requestName, requestTarget, ledgerKey, label, idLog)
 local remain = requestCount - bridgeCount
 if remain > 0 then
 local craftObject = craftHandler(request, bridgeItem, bridge, remain, label, idLog)
 end
 else
 if doLogExtra then logLine("[CASE 3] Bridge Item - Craft") end
 local craftObject = craftHandler(request, bridgeItem, bridge, requestCount, label, idLog)
 end
 end
 -- [CASE 4] These items are not in stock, and/or don't have a recipe.
 else
 if requestCount <= 0 then
 if doLogExtra then logLine(string.format("[CASE 4] Skipped (export ledger) [%s]", debugInfo)) end
 else
 if doLogExtra then logLine(string.format("[CASE 4] Bridge Item - No Craft, Only Manual[%s]", debugInfo)) end
 local domum = domumHandler(request)
 local craftObject = craftHandler(request, bridgeItem, bridge, requestCount, label, idLog)
 end
 end
 end
 end
end

-- [MAIN LOOP] --------------------------------------------------------------------------------------------------------
cleanupOldLogs()
loadExportLedger()
if exportLedgerFile and #exportLedgerFile > 0 then
 print(string.format("[ae2Colony] Export ledger file: %s", exportLedgerFile))
end
local bridge, colony, monitor = setupPeripherals()
local title = string.format("[INFO] %s v%s initialized", scriptName, scriptVersion)
print(title)
logLine(title)
if exportChestPeripheral and #exportChestPeripheral > 0 then
 print(string.format("[ae2Colony] ME export -> peripheral '%s' (exportSide ignored).", exportChestPeripheral))
else
 print(string.format("[ae2Colony] ME export -> bridge side '%s'. Chest not filling? Change exportSide (see docs/SIMPLE-RU.md).", exportSide))
end

local function main()
 local tick = scanInterval
 local nextUiMs = 0
 while true do
 exportBuffer = {}
 monitorLines = {}
 monitorColonyPrefixLines = {}
 local nowScan = os.epoch("utc")
 if nowScan >= nextUiMs then
 colonyUiSnapshot = fetchColonyUiSnapshot(colony, nowScan)
 nextUiMs = nowScan + (colonyUiInterval * 1000)
 end
 for _, ln in ipairs(colonyUiSnapshot.lines) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 for _, ln in ipairs(colonyUiSnapshot.needsLines or {}) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 mainHandler(bridge, colony)
 processExportBuffer(bridge)
 refreshMonitorBody(monitor)

 while tick > 0 do
 local now = os.epoch("utc")
 if now >= nextUiMs then
 colonyUiSnapshot = fetchColonyUiSnapshot(colony, now)
 nextUiMs = now + (colonyUiInterval * 1000)
 monitorColonyPrefixLines = {}
 for _, ln in ipairs(colonyUiSnapshot.lines) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 for _, ln in ipairs(colonyUiSnapshot.needsLines or {}) do
  table.insert(monitorColonyPrefixLines, ln)
 end
 refreshMonitorBody(monitor)
 end
 local online = confirmConnection(bridge)
 if online then
 tick = tick - 1
 end
 updateHeader(monitor, bridge, tick, colonyUiSnapshot)
 os.sleep(1)
 end
 tick = scanInterval
 end
end

parallel.waitForAll(
 main,
 function() handleMonitorTouch(monitor, bridge, colony) end
)
