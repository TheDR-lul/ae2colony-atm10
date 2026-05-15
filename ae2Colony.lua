local scriptName = "AE2 Colony"
local scriptVersion = "0.6.3-atm10"
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
Public repo: github.com/TheDR-lul/ae2colony-atm10 only. Do not use raw.githubusercontent.com/.../smarthome/... (private -> 404 in-game).
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
local alarm = nil -- Used to update monitor for errors (getRequests failure); see alarmInfo + alerts.

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
-- Also merge colony.getBuilderResources(builderPos) into NEEDS (often closer to the in-game construction list).
local mergeBuilderHutResources = true
-- Work orders often omit wrow.builder; AP documents builderHome. When still no coords, scan getBuildings() for builder huts.
local mergeBuilderHutAutoScan = true
-- Same item from WO + builder APIs often duplicates; "max" avoids inflated counts. Use "sum" only if you know you need additive merge.
local constructionNeedDuplicateMerge = "max"
-- Hide NOT_NEEDED rows so the list matches "still owe the build"; set false to debug raw API rows.
local constructionNeedsHideNotNeeded = true
-- After footer CRAFT+EXPORT: keep exporting as ME finishes autocrafts (non-blocking drain).
local constructionPushDrainAfterCraft = true
local constructionPushDrainPollSeconds = 1
local constructionPushDrainTimeoutSeconds = 180
local constructionPushDrainMaxPerTick = 4
-- Header line 2: show ME crafting CPU busy count (and spinner when crafting or drain pending).
local showMeCraftingStatus = true
local showMeCraftingSpinner = true
-- Extra header line (line 3): progress bar + last craft orders (needs monitor height >= 8).
local showMeCraftingHudLine = true
-- Optional NEEDS diff vs previous colony UI refresh (same keys as internal need map).
local showConstructionNeedsDiff = false
local constructionNeedsDiffMaxLines = 4
-- Pinned [ALERT] lines at top of monitor body (max count); see docs/ALERTS.md
local pinnedAlertsMaxLines = 3
-- Speaker / redstone alerts (debounced). Peripheral: same network or `speakerPeripheralName`.
local alerts = {
 enabled = false,
 minIntervalSec = 10,
 useSpeaker = true,
 speakerPeripheralName = nil,
 useRedstone = false,
 redstoneSide = "back",
 redstonePulseTicks = 2,
 onRaid = true,
 onMeOffline = true,
 onMeOnline = false,
 onMissingPattern = true,
 onPostCraftTimeout = true,
 onGetBuildingsBreaker = true,
 onColonyRequestsCritical = true,
 onCraftStarted = false,
}
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

local pendingPostCraftExport = {}
local lastPostCraftDrainMs = 0
-- Last N craft orders started (for HUD "what went to craft").
local recentCraftOrders = {}
-- Pinned monitor rows (rebuilt before each body draw).
local pinnedDisplayLines = {}
-- NEEDS diff: previous snapshot map key -> { needed, status, label }
local lastNeedsForDiff = nil
local triggerAlert
-- Footer: [TEST] + mode chip (mute when alerts on, or [A:ON]/[A:OFF] toggle when off).
local showAlertsMuteButton = true
local alertsMuted = false
local alertsMutedFile = "ae2colony_alerts_muted.txt"
-- If this file exists, it overrides alerts.enabled after config (true/false).
local alertsMonitorOverrideFile = "ae2colony_alerts_monitor_enabled.txt"
local FOOTER_ALERT_TEST_CHARS = 6
local FOOTER_ALERT_SCAN_CHARS = 6
local FOOTER_ALERT_MODE_CHARS = 8
-- [SCAN] needs room for craft + mode + scan + test (see footerAlertBarLayout).
local FOOTER_MIN_MONITOR_W_FOR_SCAN_BUTTON = 16

-- Monitor layout: "classic" (single column) or "scada" (split body; needs scada.enabled + wide monitor).
local uiMode = "classic"
-- Experimental SCADA metrics (citizen saturation, ME food whitelist, local heuristic trends). See docs/SCADA.md.
local scada = {
 enabled = false,
 intervalSec = 15,
 minMonitorWidth = 26,
 leftBodyFraction = 0.58,
 saturationWarnBelow = 8,
 foodWhitelist = {
 "minecraft:bread",
 "minecraft:cooked_beef",
 "minecraft:baked_potato",
 "minecraft:carrot",
 "minecraft:cooked_porkchop",
 },
 scanMeFoodFromWhitelist = true,
 historyFile = "ae2colony_scada_history.jsonl",
 historySampleSec = 60,
 maxHistoryPoints = 48,
 trendWindowPoints = 10,
 warnTrendDropCycles = 3,
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
 if tbl.mergeBuilderHutResources ~= nil then
 mergeBuilderHutResources = tbl.mergeBuilderHutResources
 end
 if tbl.mergeBuilderHutAutoScan ~= nil then
 mergeBuilderHutAutoScan = tbl.mergeBuilderHutAutoScan
 end
 if tbl.constructionNeedDuplicateMerge == "sum" or tbl.constructionNeedDuplicateMerge == "max" then
 constructionNeedDuplicateMerge = tbl.constructionNeedDuplicateMerge
 end
 if tbl.constructionNeedsHideNotNeeded ~= nil then
 constructionNeedsHideNotNeeded = tbl.constructionNeedsHideNotNeeded
 end
 if tbl.constructionPushDrainAfterCraft ~= nil then
 constructionPushDrainAfterCraft = tbl.constructionPushDrainAfterCraft
 end
 if tbl.constructionPushDrainPollSeconds ~= nil then
 constructionPushDrainPollSeconds = tonumber(tbl.constructionPushDrainPollSeconds) or constructionPushDrainPollSeconds
 end
 if tbl.constructionPushDrainTimeoutSeconds ~= nil then
 constructionPushDrainTimeoutSeconds = tonumber(tbl.constructionPushDrainTimeoutSeconds) or constructionPushDrainTimeoutSeconds
 end
 if tbl.constructionPushDrainMaxPerTick ~= nil then
 constructionPushDrainMaxPerTick = tonumber(tbl.constructionPushDrainMaxPerTick) or constructionPushDrainMaxPerTick
 end
 if tbl.showMeCraftingStatus ~= nil then
 showMeCraftingStatus = tbl.showMeCraftingStatus
 end
 if tbl.showMeCraftingSpinner ~= nil then
 showMeCraftingSpinner = tbl.showMeCraftingSpinner
 end
 if tbl.showMeCraftingHudLine ~= nil then
 showMeCraftingHudLine = tbl.showMeCraftingHudLine
 end
 if tbl.showConstructionNeedsDiff ~= nil then
 showConstructionNeedsDiff = tbl.showConstructionNeedsDiff
 end
 if tbl.constructionNeedsDiffMaxLines ~= nil then
 constructionNeedsDiffMaxLines = tonumber(tbl.constructionNeedsDiffMaxLines) or constructionNeedsDiffMaxLines
 end
 if tbl.pinnedAlertsMaxLines ~= nil then
 pinnedAlertsMaxLines = tonumber(tbl.pinnedAlertsMaxLines) or pinnedAlertsMaxLines
 end
 if type(tbl.alerts) == "table" then
 for ak, av in pairs(tbl.alerts) do
 alerts[ak] = av
 end
 end
 if tbl.showAlertsMuteButton ~= nil then
 showAlertsMuteButton = tbl.showAlertsMuteButton
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
 if tbl.uiMode == "classic" or tbl.uiMode == "scada" then
 uiMode = tbl.uiMode
 end
 if type(tbl.ui) == "table" and (tbl.ui.mode == "classic" or tbl.ui.mode == "scada") then
 uiMode = tbl.ui.mode
 end
 if type(tbl.scada) == "table" then
 for sk, sv in pairs(tbl.scada) do
 if sk == "foodWhitelist" and type(sv) == "table" then
 scada.foodWhitelist = sv
 else
 scada[sk] = sv
 end
 end
 end
 print("[ae2Colony] Merged ae2colony_config.lua")
end

local function loadAlertsMuted()
 alertsMuted = false
 if not fs.exists(alertsMutedFile) then
 return
 end
 local f = fs.open(alertsMutedFile, "r")
 if not f then
 return
 end
 local s = f.readAll()
 f.close()
 if type(s) == "string" and s:find("true", 1, true) then
 alertsMuted = true
 end
end

local function saveAlertsMuted()
 local f = fs.open(alertsMutedFile, "w")
 if f then
 f.write(alertsMuted and "true" or "false")
 f.close()
 end
end

local function loadAlertsMonitorOverride()
 if not fs.exists(alertsMonitorOverrideFile) then
 return
 end
 local f = fs.open(alertsMonitorOverrideFile, "r")
 if not f then
 return
 end
 local s = f.readAll()
 f.close()
 if type(s) ~= "string" then
 return
 end
 if s:find("true", 1, true) then
 alerts.enabled = true
 elseif s:find("false", 1, true) then
 alerts.enabled = false
 end
end

local function saveAlertsMonitorOverride(on)
 local f = fs.open(alertsMonitorOverrideFile, "w")
 if f then
 f.write(on and "true" or "false")
 f.close()
 end
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

local colonyUiSnapshot = {
 headerCompact = "",
 lines = {},
 needsLines = {},
 needsEntries = {},
 underAttack = false,
 breakerActive = false,
 breakerJustTripped = false,
 happiness = nil,
 citizensCur = nil,
 citizensMax = nil,
}

-- AP / CC may return resource lists as sparse arrays, mixed maps, or { resources = {...} }; #tbl is then wrong.
local function collectResourceRows(res)
 local rows = {}
 if type(res) ~= "table" then
 return rows
 end
 if type(res.resources) == "table" then
 return collectResourceRows(res.resources)
 end
 local maxk = 0
 for k, _ in pairs(res) do
 if type(k) == "number" and k > maxk then
 maxk = k
 end
 end
 for i = 1, maxk do
 local v = res[i]
 if type(v) == "table" then
 rows[#rows + 1] = v
 end
 end
 if #rows == 0 then
 for _, v in pairs(res) do
 if type(v) == "table" and (v.item or v.name or v.displayName or v.id) then
 rows[#rows + 1] = v
 end
 end
 end
 return rows
end

local function itemIdFromNeedRow(r)
 if type(r) ~= "table" then
 return nil
 end
 local it = r.item
 if type(it) == "string" and #it > 0 then
 return it
 end
 if type(it) == "table" then
 if type(it.name) == "string" and #it.name > 0 then
 return it.name
 end
 if type(it.id) == "string" and #it.id > 0 then
 return it.id
 end
 end
 if type(r.name) == "string" and #r.name > 0 then
 return r.name
 end
 if type(r.id) == "string" and #r.id > 0 and r.id:find(":") then
 return r.id
 end
 return nil
end

local function quantityFromNeedRow(r)
 if type(r) ~= "table" then
 return 1
 end
 local function num(x)
 if type(x) == "number" then
 return x
 end
 if type(x) == "string" then
 return tonumber(x)
 end
 return nil
 end
 -- Advanced Peripherals MineColonies.builderResourcesToObject:
 -- NeoForge/1.21+: "needs" = BuildingBuilderResource.getAmount() (total for the build line).
 -- Forge/1.20.x: same value was exposed as "needed". Only use numeric "available" (int count), not boolean.
 local total =
 num(r.needs)
 or num(r.needed)
 or num(r.amount)
 or num(r.total)
 or num(r.totalNeeded)
 or num(r.total_needed)
 or num(r.required)
 or num(r.targetCount)
 local avail = num(r.amountAvailable) or num(r.availableAmount) or num(r.amount_available) or num(r.delivered) or num(r.stored)
 if type(r.available) == "number" then
 avail = avail or r.available
 end
 local inflight = num(r.delivering) or 0
 local n = nil
 if total and avail ~= nil then
 n = total - avail - inflight
 if n < 1 then
 return 0
 end
 return math.floor(n + 0.5)
 end
 if not n or n < 1 then
 local need = r.needs or r.needed
 if type(need) == "number" then
 n = need
 elseif type(need) == "string" then
 n = tonumber(need)
 elseif type(need) == "table" then
 n = tonumber(need.count or need.amount or need.needed or need.needs)
 end
 end
 if not n or n < 1 then
 n = num(r.needs) or num(r.count) or num(r.amount) or num(r.missing) or num(r.remaining) or num(r.shortage) or num(r.deficit)
 end
 if not n or n < 1 then
 n = 1
 end
 return math.floor(n + 0.5)
end

local function detailSuffixFromNeedRow(r)
 if type(r) ~= "table" then
 return ""
 end
 local function num(x)
 if type(x) == "number" then
 return x
 end
 if type(x) == "string" then
 return tonumber(x)
 end
 return nil
 end
 local total =
 num(r.needs)
 or num(r.needed)
 or num(r.amount)
 or num(r.total)
 or num(r.totalNeeded)
 or num(r.total_needed)
 or num(r.required)
 or num(r.targetCount)
 local avail = num(r.amountAvailable) or num(r.availableAmount) or num(r.amount_available) or num(r.delivered) or num(r.stored)
 if type(r.available) == "number" then
 avail = avail or r.available
 end
 if total and avail then
 return string.format(" (%d/%d)", avail, total)
 end
 return ""
end

local function normalizeBlockPos(p)
 if type(p) ~= "table" then
 return nil
 end
 if p.x == nil or p.z == nil then
 return nil
 end
 return { x = p.x, y = p.y or 0, z = p.z }
end

local function isBuilderHutBuilding(b)
 if type(b) ~= "table" then
 return false
 end
 local t = tostring(b.type or ""):lower()
 if t == "" then
 return false
 end
 if t:find("buildertools", 1, true) then
 return false
 end
 return t:find("builder", 1, true) ~= nil
end

local function builderPosCandidatesFromWorkOrder(wrow)
 if type(wrow) ~= "table" then
 return {}
 end
 local out = {}
 local keys = { "builderHome", "builder", "builderPos", "buildersHut", "hutPos" }
 for _, k in ipairs(keys) do
 local pos = normalizeBlockPos(wrow[k])
 if pos then
 out[#out + 1] = pos
 end
 end
 return out
end

local function posKey(p)
 if not p then
 return nil
 end
 return string.format("%d,%d,%d", math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5))
end

local function collectBuilderHutPositionsFromBuildings(colony)
 local positions = {}
 local ok, buildings = pcall(function()
 return colony.getBuildings()
 end)
 if not ok or type(buildings) ~= "table" then
 return positions
 end
 for _, b in pairs(buildings) do
 if isBuilderHutBuilding(b) then
 local pos = normalizeBlockPos(b.pos or b.location)
 if pos then
 positions[#positions + 1] = pos
 end
 end
 end
 return positions
end

local function fetchColonyUiSnapshot(colony, nowMs)
 local lines = {}
 local needsLines = {}
 local needsEntries = {}
 local parts = {}
 local breakerJustTripped = false
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
 local underAttackFlag = (okA and attack) and true or false
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
 if showConstructionNeedsList and top > 0 then
 local needsMap = {}
 local function mergeNeedRow(woId, r)
 if type(r) ~= "table" then
 return
 end
 local name = itemIdFromNeedRow(r)
 if type(name) ~= "string" or #name == 0 then
 return
 end
 local fp = r.fingerprint
 if type(fp) == "table" and type(fp.hash) == "string" then
 fp = fp.hash
 end
 local key = (fp and tostring(fp)) or name
 local n = quantityFromNeedRow(r)
 local st = tostring(r.status or "?")
 local comps = r.components
 if type(comps) ~= "table" then
 comps = {}
 end
 local sfx = detailSuffixFromNeedRow(r)
 local prev = needsMap[key]
 if prev then
 if constructionNeedDuplicateMerge == "sum" then
 prev.needed = prev.needed + n
 else
 prev.needed = math.max(prev.needed, n)
 end
 if st == "DONT_HAVE" then
 prev.status = "DONT_HAVE"
 end
 if sfx and #sfx > 0 then
 prev.detailSuffix = sfx
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
 detailSuffix = sfx and #sfx > 0 and sfx or "",
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
 local rows = collectResourceRows(res)
 for _, row in ipairs(rows) do
 mergeNeedRow(wrow.id, row)
 end
 end
 end
 end

 if mergeBuilderHutResources then
 local mergedBuilderPos = {}
 local function tryMergeBuilderAt(bp, woId)
 local k = posKey(bp)
 if not k or mergedBuilderPos[k] then
 return
 end
 local okBr, bred = pcall(function()
 return colony.getBuilderResources({
 x = bp.x,
 y = bp.y or 0,
 z = bp.z,
 })
 end)
 if okBr and type(bred) == "table" then
 mergedBuilderPos[k] = true
 local brows = collectResourceRows(bred)
 for _, row in ipairs(brows) do
 mergeNeedRow(woId, row)
 end
 end
 end

 for wi = 1, woLimit do
 local wrow = list[wi]
 if wrow and wrow.id ~= nil then
 local wid = wrow.id
 for _, bp in ipairs(builderPosCandidatesFromWorkOrder(wrow)) do
 tryMergeBuilderAt(bp, wid)
 end
 end
 end

 if mergeBuilderHutAutoScan then
 local nMerged = 0
 for _ in pairs(mergedBuilderPos) do
 nMerged = nMerged + 1
 end
 if nMerged == 0 then
 local scanPositions = collectBuilderHutPositionsFromBuildings(colony)
 local fallbackWoId = list[1] and list[1].id or "builder-scan"
 for _, bp in ipairs(scanPositions) do
 tryMergeBuilderAt(bp, fallbackWoId)
 end
 end
 end
 end

 local flat = {}
 for _, row in pairs(needsMap) do
 if not (constructionNeedsHideNotNeeded and tostring(row.status or "") == "NOT_NEEDED") then
 flat[#flat + 1] = row
 end
 end
 table.sort(flat, function(a, b)
 local sa = a.status == "DONT_HAVE" and 0 or 1
 local sb = b.status == "DONT_HAVE" and 0 or 1
 if sa ~= sb then
 return sa < sb
 end
 return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
 end)
 if #flat > 0 then
 local tr = flat[1]
 local tlab = tr.displayName or prettifyItemId(tr.name or "?")
 local sfx = tr.detailSuffix or ""
 table.insert(
 lines,
 string.format("[COLONY] Top need: %s x%d (%s)%s", tlab, tr.needed, tr.status, sfx)
 )
 local dontHaveRows = 0
 for _, row in ipairs(flat) do
 if tostring(row.status or "") == "DONT_HAVE" then
 dontHaveRows = dontHaveRows + 1
 end
 end
 if dontHaveRows > 0 then
 table.insert(
 lines,
 string.format("[COLONY] Blocking: %d DONT_HAVE (of %d listed)", dontHaveRows, #flat)
 )
 end
 end
 local cap = math.max(1, constructionNeedsMaxItems or 14)
 for i = 1, math.min(#flat, cap) do
 local row = flat[i]
 local label = row.displayName or prettifyItemId(row.name)
 local extra = row.status == "DONT_HAVE" and " !" or ""
 local sfx = row.detailSuffix or ""
 table.insert(
 needsLines,
 string.format("[NEEDS] %s x%d %s%s%s", label, row.needed, row.status, extra, sfx)
 )
 needsEntries[#needsEntries + 1] = {
 workOrderId = row.workOrderId,
 name = row.name,
 fingerprint = row.fingerprint,
 displayName = row.displayName,
 needed = row.needed,
 status = row.status,
 components = row.components,
 detailSuffix = row.detailSuffix,
 }
 end
 if #flat > cap then
 table.insert(needsLines, string.format("[NEEDS] ... +%d more (see log)", #flat - cap))
 end
 elseif showConstructionDetail and top > 0 and list[1] and list[1].id ~= nil then
 local okR, res = pcall(function()
 return colony.getWorkOrderResources(list[1].id)
 end)
 if okR and type(res) == "table" then
 local rows = collectResourceRows(res)
 if #rows > 0 then
 local r = rows[1]
 local rn = r.displayName or itemIdFromNeedRow(r) or "?"
 local rq = quantityFromNeedRow(r)
 table.insert(
 lines,
 string.format("[COLONY] Top need: %s x%s (%s)", tostring(rn), tostring(rq), tostring(r.status or "?"))
 )
 end
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
 breakerJustTripped = true
 table.insert(lines, "[WARN] getBuildings disabled (API error; see docs)")
 end
 end
 if showConstructionNeedsDiff then
 if type(needsEntries) == "table" and #needsEntries > 0 then
 local function needDiffKey(e)
 return tostring(e.fingerprint or "")
 .. "|"
 .. tostring(e.name or "")
 .. "|"
 .. tostring(e.workOrderId or "")
 end
 local newMap = {}
 for _, e in ipairs(needsEntries) do
 local k = needDiffKey(e)
 newMap[k] = {
 needed = tonumber(e.needed) or 0,
 status = tostring(e.status or "?"),
 label = tostring(e.displayName or prettifyItemId(e.name or "?")),
 }
 end
 if type(lastNeedsForDiff) == "table" then
 local diffBuf = {}
 for k, nv in pairs(newMap) do
 local ov = lastNeedsForDiff[k]
 if not ov then
 table.insert(diffBuf, string.format("[NEEDS] + %s x%d %s", nv.label, nv.needed, nv.status))
 elseif ov.needed ~= nv.needed or ov.status ~= nv.status then
 table.insert(
 diffBuf,
 string.format("[NEEDS] ~ %s x%d->x%d %s", nv.label, ov.needed, nv.needed, nv.status)
 )
 end
 end
 for k, ov in pairs(lastNeedsForDiff) do
 if not newMap[k] then
 table.insert(diffBuf, string.format("[NEEDS] - %s (was x%d)", ov.label, ov.needed))
 end
 end
 table.sort(diffBuf)
 local cap = math.max(1, constructionNeedsDiffMaxLines or 4)
 local toShow = math.min(#diffBuf, cap)
 for i = toShow, 1, -1 do
 table.insert(needsLines, 1, diffBuf[i])
 end
 end
 lastNeedsForDiff = newMap
 else
 lastNeedsForDiff = {}
 end
 end
 return {
 headerCompact = table.concat(parts, " | "),
 lines = lines,
 needsLines = needsLines,
 needsEntries = needsEntries,
 underAttack = underAttackFlag,
 breakerActive = (buildingsDisabledUntil or 0) > nowMs,
 breakerJustTripped = breakerJustTripped,
 happiness = (okH and happy ~= nil) and tonumber(happy) or nil,
 citizensCur = (okC and cur ~= nil) and tonumber(cur) or nil,
 citizensMax = (okM and maxc ~= nil) and tonumber(maxc) or nil,
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
loadAlertsMuted()
loadAlertsMonitorOverride()

-- [SCADA snapshot + heuristic history] -------------------------------------------------------------------------------
local scadaSnapshot = {
 errorCitizens = nil,
 citizenCount = 0,
 citizensWithSat = 0,
 avgSat = nil,
 minSat = nil,
 lowSatCount = 0,
 lowSamples = {},
 meFood = {},
 meFoodError = nil,
 satSlopePerStep = nil,
 trendWarn = false,
 heuristicLine = nil,
 lastMs = 0,
}

local scadaHistoryRing = {}
local lastScadaHistoryAppendMs = 0
local satTrendNegStreak = 0

local function trimScadaHistoryRing()
 local cap = math.max(4, tonumber(scada.maxHistoryPoints) or 48)
 while #scadaHistoryRing > cap do
 table.remove(scadaHistoryRing, 1)
 end
end

local function appendScadaHistoryRow(row)
 local path = scada.historyFile
 if type(path) ~= "string" or #path < 1 then
 return
 end
 local f = fs.open(path, "a")
 if f then
 f.writeLine(textutils.serialize(row))
 f.close()
 end
 scadaHistoryRing[#scadaHistoryRing + 1] = row
 trimScadaHistoryRing()
end

local function recomputeAvgSatSlopePerStep()
 local w = math.min(math.max(2, tonumber(scada.trendWindowPoints) or 10), #scadaHistoryRing)
 if w < 2 or #scadaHistoryRing < 2 then
 return nil
 end
 local start = #scadaHistoryRing - w + 1
 local sumx, sumy, sumxx, sumxy, n = 0, 0, 0, 0, 0
 local x = 1
 for i = start, #scadaHistoryRing do
 local s = tonumber(scadaHistoryRing[i].avgSat)
 if s then
 sumx = sumx + x
 sumy = sumy + s
 sumxx = sumxx + x * x
 sumxy = sumxy + x * s
 n = n + 1
 x = x + 1
 end
 end
 if n < 2 then
 return nil
 end
 local denom = n * sumxx - sumx * sumx
 if denom == 0 then
 return nil
 end
 return (n * sumxy - sumx * sumy) / denom
end

local function fetchScadaSnapshot(colony, bridge, nowMs)
 local out = {
 errorCitizens = nil,
 citizenCount = 0,
 citizensWithSat = 0,
 avgSat = nil,
 minSat = nil,
 lowSatCount = 0,
 lowSamples = {},
 meFood = {},
 meFoodError = nil,
 satSlopePerStep = nil,
 trendWarn = false,
 heuristicLine = nil,
 lastMs = nowMs,
 }
 local thr = tonumber(scada.saturationWarnBelow) or 8
 local okC, citizens = pcall(function()
 return colony.getCitizens()
 end)
 if not okC or type(citizens) ~= "table" then
 out.errorCitizens = "getCitizens() failed"
 else
 local sum = 0
 local nSat = 0
 local minS = nil
 local low = {}
 local nCit = 0
 for _, c in pairs(citizens) do
 if type(c) == "table" then
 nCit = nCit + 1
 local sat = tonumber(c.saturation)
 if sat == nil and c.saturation ~= nil then
 sat = tonumber(tostring(c.saturation))
 end
 if sat ~= nil then
 nSat = nSat + 1
 sum = sum + sat
 minS = minS and math.min(minS, sat) or sat
 if sat < thr then
 out.lowSatCount = out.lowSatCount + 1
 low[#low + 1] = { name = tostring(c.name or "?"), sat = sat }
 end
 end
 end
 out.citizenCount = nCit
 out.citizensWithSat = nSat
 if nSat > 0 then
 out.avgSat = sum / nSat
 out.minSat = minS
 table.sort(low, function(a, b)
 return a.sat < b.sat
 end)
 for i = 1, math.min(3, #low) do
 out.lowSamples[#out.lowSamples + 1] = low[i]
 end
 end
 end
 if scada.scanMeFoodFromWhitelist and bridge and type(bridge.getItem) == "function" then
 local wl = scada.foodWhitelist
 if type(wl) == "table" then
 for _, id in ipairs(wl) do
 if type(id) == "string" and #id > 0 then
 local okG, it = pcall(function()
 return bridge.getItem({ name = id, count = 1, components = {} })
 end)
 if okG and type(it) == "table" then
 local cnt = tonumber(it.count) or 0
 out.meFood[#out.meFood + 1] = { name = id, count = cnt }
 elseif not okG then
 out.meFoodError = "getItem failed"
 break
 end
 end
 end
 end
 elseif scada.scanMeFoodFromWhitelist then
 out.meFoodError = "no getItem"
 end
 local sampleMs = math.max(15, tonumber(scada.historySampleSec) or 60) * 1000
 if out.avgSat ~= nil and (nowMs - lastScadaHistoryAppendMs) >= sampleMs then
 lastScadaHistoryAppendMs = nowMs
 appendScadaHistoryRow({
 t = nowMs,
 avgSat = out.avgSat,
 happiness = colonyUiSnapshot.happiness,
 citizens = colonyUiSnapshot.citizensCur,
 })
 end
 out.satSlopePerStep = recomputeAvgSatSlopePerStep()
 local slope = out.satSlopePerStep
 if slope and slope < -0.02 then
 satTrendNegStreak = satTrendNegStreak + 1
 else
 satTrendNegStreak = 0
 end
 local needN = tonumber(scada.warnTrendDropCycles) or 3
 out.trendWarn = satTrendNegStreak >= needN
 if slope then
 out.heuristicLine = string.format("est.sat/step:%.3f (heur.)", slope)
 else
 out.heuristicLine = "est.sat: n/a (heur.)"
 end
 return out
end

local nextScadaMs = 0

local alertKindToConfig = {
 raid = "onRaid",
 me_offline = "onMeOffline",
 me_online = "onMeOnline",
 missing_pattern = "onMissingPattern",
 post_craft_timeout = "onPostCraftTimeout",
 get_buildings_breaker = "onGetBuildingsBreaker",
 colony_requests_critical = "onColonyRequestsCritical",
 craft_started = "onCraftStarted",
}
local lastAlertFireMs = {}
local speakerCache = nil

local function getSpeakerPeripheral()
 if speakerCache == false then
 return nil
 end
 if type(speakerCache) == "table" then
 return speakerCache
 end
 local name = alerts.speakerPeripheralName
 local wrap
 if type(name) == "string" and #name > 0 then
 wrap = peripheral.wrap(name)
 else
 local n = peripheral.find("speaker")
 if type(n) == "string" and #n > 0 then
 wrap = peripheral.wrap(n)
 elseif type(n) == "table" then
 wrap = n
 end
 end
 if wrap and type(wrap.playNote) == "function" then
 speakerCache = wrap
 return wrap
 end
 speakerCache = false
 return nil
end

local function scanSpeakersAndReport()
 speakerCache = nil
 local found = {}
 for _, nm in ipairs(peripheral.getNames()) do
 local ok, ty = pcall(peripheral.getType, nm)
 if ok and ty == "speaker" then
 found[#found + 1] = tostring(nm)
 end
 end
 table.sort(found)
 if #found < 1 then
 print("[ae2Colony] Speaker scan: none on this computer's network (modem + speaker?).")
 else
 print(string.format("[ae2Colony] Speaker scan: %d — %s", #found, table.concat(found, ", ")))
 end
 return found
end

local function playSpeakerPattern(pattern)
 if not alerts.useSpeaker then
 return
 end
 local sp = getSpeakerPeripheral()
 if not sp then
 return
 end
 for _, n in ipairs(pattern) do
 local inst = n[1] or "harp"
 local vol = n[2] or 1
 local pitch = n[3] or 12
 pcall(function()
 sp.playNote(inst, vol, pitch)
 end)
 os.sleep(0.08)
 end
end

local function playSpeakerTestBeep()
 local sp = getSpeakerPeripheral()
 if not sp then
 print("[ae2Colony] Speaker test: no speaker (attach speaker + wired modem).")
 return false
 end
 local ok = pcall(function()
 sp.playNote("harp", 2, 15)
 end)
 if ok then
 print("[ae2Colony] Speaker test: beep OK.")
 else
 print("[ae2Colony] Speaker test: playNote failed.")
 end
 return ok
end

local function pulseRedstoneAlert()
 if not alerts.useRedstone then
 return
 end
 local side = alerts.redstoneSide or "back"
 local ticks = math.max(1, tonumber(alerts.redstonePulseTicks) or 2)
 pcall(function()
 redstone.setOutput(side, true)
 end)
 os.sleep(0.05 * ticks)
 pcall(function()
 redstone.setOutput(side, false)
 end)
end

triggerAlert = function(kind)
 if alertsMuted then
 return
 end
 if not alerts.enabled then
 return
 end
 local cfgKey = alertKindToConfig[kind]
 if not cfgKey or not alerts[cfgKey] then
 return
 end
 local minMs = math.max(500, (tonumber(alerts.minIntervalSec) or 10) * 1000)
 local now = os.epoch("utc")
 local last = lastAlertFireMs[kind] or 0
 if now - last < minMs then
 return
 end
 lastAlertFireMs[kind] = now
 local patterns = {
 raid = {
 { "bell", 2, 12 },
 { "bell", 2, 14 },
 { "bell", 2, 12 },
 },
 me_offline = { { "bass", 2, 6 } },
 me_online = { { "harp", 1, 14 } },
 missing_pattern = { { "bit", 1, 8 }, { "bit", 1, 6 } },
 post_craft_timeout = { { "bass", 2, 4 }, { "bass", 2, 2 } },
 get_buildings_breaker = { { "hat", 1, 5 } },
 colony_requests_critical = { { "bass", 3, 2 }, { "bass", 3, 4 } },
 craft_started = { { "harp", 1, 10 }, { "harp", 1, 12 } },
 }
 local pat = patterns[kind]
 if pat then
 playSpeakerPattern(pat)
 end
 pulseRedstoneAlert()
end

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

local function buildGroupedMonitorFlatLines()
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
 table.insert(flatLines, { text = "== " .. label .. " ==", color = colors.white })
 local cap = maxLinesPerGroup or 12
 for j = 1, math.min(#entries, cap) do
 table.insert(flatLines, { text = entries[j], color = colorsMap[label] or colors.white })
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
 local pin = pinnedDisplayLines or {}
 local pinFlat = {}
 local pinMax = math.min(#pin, math.max(0, tonumber(pinnedAlertsMaxLines) or 3))
 for i = 1, pinMax do
 local row = pin[i]
 if row and type(row.text) == "string" then
 pinFlat[#pinFlat + 1] = { text = row.text, color = row.color or colors.red }
 end
 end
 if #pinFlat > 0 then
 local merged = {}
 for i = 1, #pinFlat do
 merged[#merged + 1] = pinFlat[i]
 end
 for i = 1, #flatLines do
 merged[#merged + 1] = flatLines[i]
 end
 flatLines = merged
 end
 return flatLines
end

local function clipStr(s, w)
 if type(s) ~= "string" then
 return ""
 end
 if #s <= w then
 return s
 end
 if w < 4 then
 return ""
 end
 return s:sub(1, w - 2) .. ".."
end

local function buildScadaRightPanelLines(maxRows, rightW, snap)
 local rows = {}
 local function push(txt, col)
 if #rows >= maxRows then
 return
 end
 rows[#rows + 1] = { text = clipStr(txt, rightW), color = col or colors.lightGray }
 end
 if maxRows < 1 or rightW < 4 then
 return rows
 end
 push("== SCADA ==", colors.white)
 if snap.errorCitizens then
 push("[WARN] " .. snap.errorCitizens, colors.orange)
 end
 push(
 string.format(
 "Cit:%d satN:%d",
 tonumber(snap.citizenCount) or 0,
 tonumber(snap.citizensWithSat) or 0
 ),
 colors.lightBlue
 )
 if snap.avgSat then
 push(
 string.format(
 "avgSat:%.1f min:%s",
 snap.avgSat,
 snap.minSat ~= nil and string.format("%.1f", snap.minSat) or "?"
 ),
 colors.lime
 )
 else
 push("avgSat: n/a", colors.gray)
 end
 if (snap.lowSatCount or 0) > 0 then
 push(string.format("LOW sat: %d", snap.lowSatCount), colors.magenta)
 for _, s in ipairs(snap.lowSamples or {}) do
 push(string.format(" %s %.1f", tostring(s.name):sub(1, 10), s.sat), colors.magenta)
 end
 end
 if snap.meFoodError then
 push("ME: " .. snap.meFoodError, colors.orange)
 end
 for _, e in ipairs(snap.meFood or {}) do
 local short = prettifyItemId(e.name)
 push(string.format("%s:%d", short, tonumber(e.count) or 0), colors.yellow)
 end
 if snap.heuristicLine then
 push(snap.heuristicLine, colors.gray)
 end
 if snap.trendWarn then
 push("[WARN] sat trend down", colors.red)
 end
 while #rows < maxRows do
 push("", colors.black)
 end
 return rows
end

local function updateMonitorGrouped(monitor)
 if not monitor then return end

 local width, height = monitor.getSize()
 local footerReserved = (height >= 5)
 and (showConstructionPushFooter or showAlertsMuteButton)
 and 1
 or 0
 local reserved = footerReserved
 local craftHudRows = (showMeCraftingHudLine and height >= 8) and 1 or 0
 reserved = reserved + craftHudRows
 local maxLines = height - 2 - reserved
 local flatLines = buildGroupedMonitorFlatLines()

 totalPages = math.max(1, math.ceil(math.max(1, #flatLines) / math.max(1, maxLines)))
 if currentPage > totalPages then currentPage = 1 end
 local startLine = (currentPage - 1) * maxLines + 1
 local endLine = math.min(startLine + maxLines - 1, #flatLines)

 local bodyStartY = 3 + craftHudRows
 for y = bodyStartY, height do
 monitor.setCursorPos(1, y)
 monitor.write(string.rep(" ", width))
 end

 local minW = tonumber(scada.minMonitorWidth) or 26
 local useScada = scada.enabled and uiMode == "scada" and width >= minW and maxLines >= 3
 local leftW = 0
 local sepW = 1
 local rightW = 0
 if useScada then
 leftW = math.floor(width * (tonumber(scada.leftBodyFraction) or 0.58))
 leftW = math.max(8, math.min(leftW, width - 9))
 rightW = width - leftW - sepW
 if rightW < 8 then
 useScada = false
 end
 end
 if useScada then
 local rightLines = buildScadaRightPanelLines(maxLines, rightW, scadaSnapshot)
 local y = bodyStartY
 for r = 1, maxLines do
 local i = startLine + r - 1
 monitor.setCursorPos(1, y)
 if i <= #flatLines then
 monitor.setTextColor(flatLines[i].color)
 local lt = clipStr(flatLines[i].text, leftW)
 monitor.write(lt)
 if #lt < leftW then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", leftW - #lt))
 end
 else
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", leftW))
 end
 monitor.setCursorPos(leftW + 1, y)
 monitor.setTextColor(colors.gray)
 monitor.write("|")
 local rr = rightLines[r]
 if rr then
 monitor.setCursorPos(leftW + sepW + 1, y)
 monitor.setTextColor(rr.color)
 local rt = clipStr(rr.text, rightW)
 monitor.write(rt)
 if #rt < rightW then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", rightW - #rt))
 end
 end
 y = y + 1
 end
 return
 end

 local y = bodyStartY
 if #flatLines > 0 then
 for i = startLine, endLine do
 monitor.setCursorPos(1, y)
 monitor.setTextColor(flatLines[i].color)
 monitor.write(flatLines[i].text:sub(1, width))
 y = y + 1
 end
 end
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

local function rebuildPinnedLines(bridge, snap)
 pinnedDisplayLines = {}
 if not snap then
 return
 end
 local cap = math.max(1, tonumber(pinnedAlertsMaxLines) or 3)
 local function add(msg, col)
 if #pinnedDisplayLines >= cap then
 return
 end
 pinnedDisplayLines[#pinnedDisplayLines + 1] = { text = msg, color = col }
 end
 if bridge and not confirmConnection(bridge) then
 add("[ALERT] ME bridge OFFLINE", colors.red)
 end
 if snap.underAttack then
 add("[ALERT] Colony UNDER ATTACK", colors.red)
 end
 if snap.breakerActive then
 add("[ALERT] getBuildings API disabled (breaker)", colors.orange)
 end
end

local function footerAlertBarLayout(w)
 if not showAlertsMuteButton or w < 8 then
 return nil
 end
 local testW = math.min(FOOTER_ALERT_TEST_CHARS, w - 1)
 local xTest = w - testW + 1
 local scanW = 0
 local xScan = nil
 if w >= FOOTER_MIN_MONITOR_W_FOR_SCAN_BUTTON then
 scanW = math.min(FOOTER_ALERT_SCAN_CHARS, xTest - 2)
 if scanW >= 4 then
 xScan = xTest - scanW
 end
 end
 local clusterLeft = xScan or xTest
 local modeW = math.min(FOOTER_ALERT_MODE_CHARS, math.max(0, clusterLeft - 2))
 local xMode = nil
 local craftMax = clusterLeft - 1
 if modeW >= 1 then
 xMode = clusterLeft - modeW
 craftMax = xMode - 1
 if craftMax < 0 then
 craftMax = 0
 modeW = math.max(0, clusterLeft - 1)
 xMode = clusterLeft - modeW
 if modeW < 1 then
 modeW = 0
 xMode = nil
 craftMax = clusterLeft - 1
 end
 end
 else
 modeW = 0
 xMode = nil
 craftMax = clusterLeft - 1
 end
 return {
 xTest = xTest,
 testW = testW,
 xScan = xScan,
 scanW = scanW,
 xMode = xMode,
 modeW = modeW,
 craftMax = craftMax,
 }
end

local function drawConstructionFooter(monitor)
 if not monitor then
 return
 end
 local w, h = monitor.getSize()
 if h < 5 then
 return
 end
 local lay = footerAlertBarLayout(w)
 if not showConstructionPushFooter and not lay then
 return
 end
 if not lay then
 lay = { craftMax = w, xTest = nil, xScan = nil, scanW = 0, xMode = nil, modeW = 0, testW = 0 }
 end
 local craftMax = lay.craftMax or 0
 if craftMax < 0 then
 craftMax = 0
 end
 monitor.setCursorPos(1, h)
 if showConstructionPushFooter and craftMax > 0 then
 local txt = ">>> CRAFT+EXPORT (NEEDS) <<<"
 if #txt > craftMax then
 txt = "> CRAFT+EXPORT <"
 end
 if #txt > craftMax then
 txt = string.sub(txt, 1, craftMax)
 end
 monitor.setTextColor(colors.yellow)
 monitor.write(txt)
 if craftMax > #txt then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", craftMax - #txt))
 end
 elseif craftMax > 0 then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", craftMax))
 end
 if lay.modeW and lay.modeW > 0 and lay.xMode then
 local modeLabel
 if alerts.enabled then
 modeLabel = alertsMuted and "[MUTED!]" or "[SND:ON]"
 else
 modeLabel = "[A:OFF]"
 end
 modeLabel = string.sub(modeLabel .. string.rep(" ", lay.modeW), 1, lay.modeW)
 monitor.setCursorPos(lay.xMode, h)
 if alerts.enabled then
 monitor.setTextColor(alertsMuted and colors.magenta or colors.lightGray)
 else
 monitor.setTextColor(colors.gray)
 end
 monitor.write(modeLabel)
 end
 if lay.xScan and (lay.scanW or 0) > 0 then
 local scanLabel = string.sub("[SCAN]" .. string.rep(" ", lay.scanW), 1, lay.scanW)
 monitor.setCursorPos(lay.xScan, h)
 monitor.setTextColor(colors.cyan)
 monitor.write(scanLabel)
 end
 if lay.xTest then
 local testLabel = string.sub("[TEST]" .. string.rep(" ", lay.testW), 1, lay.testW)
 monitor.setCursorPos(lay.xTest, h)
 monitor.setTextColor(colors.orange)
 monitor.write(testLabel)
 end
end

local function refreshMonitorBody(monitor, bridgeForPin)
 rebuildPinnedLines(bridgeForPin, colonyUiSnapshot)
 updateMonitorGrouped(monitor)
 drawConstructionFooter(monitor)
end

-- Newer me_bridge builds reject filters with only fingerprint — require a registry `name` ("mod:id") when possible.
local function meRegistryName(name)
 if type(name) ~= "string" or #name == 0 then
 return nil
 end
 if not name:find(":") then
 return nil
 end
 return name
end

local function normalizeMeFingerprint(fp)
 if type(fp) == "string" and #fp > 0 then
 return fp
 end
 if type(fp) == "table" and type(fp.hash) == "string" and #fp.hash > 0 then
 return fp.hash
 end
 return nil
end

local function buildMeItemFilter(name, fingerprint, count, components)
 local nm = meRegistryName(name)
 local fp = normalizeMeFingerprint(fingerprint)
 local comps = type(components) == "table" and components or {}
 local c = tonumber(count) or 1
 if c < 1 then
 c = 1
 end
 if nm and fp then
 return { name = nm, fingerprint = fp, count = c, components = comps }
 end
 if nm then
 return { name = nm, count = c, components = comps }
 end
 if fp then
 return { fingerprint = fp, count = c, components = comps }
 end
 return nil
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
 local filter = buildMeItemFilter(item.name, item.fingerprint, item.count, item.components)
 if not filter then
 logAndDisplay(
 string.format(
 "[ERROR] Export skipped (no valid item id): %s",
 tostring(item.idForLog or item.name or "?")
 )
 )
 else
 local ok, result = pcall(function()
 if exportChestPeripheral and #exportChestPeripheral > 0 then
 return bridge.exportItemToPeripheral(filter, exportChestPeripheral)
 end
 return bridge.exportItem(filter, exportSide)
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
 end
 if ledgerDirty then
 saveExportLedger()
 end
end

local function alarmInfo(result)
 if result ~= nil and alerts and alerts.enabled then
 triggerAlert("colony_requests_critical")
 end
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

local function countBusyCraftingCpus(bridge)
 if not bridge or type(bridge.getCraftingCPUs) ~= "function" then
 return 0
 end
 local ok, cpus = pcall(function()
 return bridge.getCraftingCPUs()
 end)
 if not ok or type(cpus) ~= "table" then
 return 0
 end
 local n = 0
 for _, c in pairs(cpus) do
 if type(c) == "table" and c.isBusy then
 n = n + 1
 end
 end
 return n
end

local meCraftSpinChars = { "|", "/", "-", "\\" }
local function pushRecentCraftOrder(label, idLog, count)
 if not showMeCraftingHudLine then
 return
 end
 local c = math.floor(tonumber(count) or 0)
 if c < 1 then
 c = 1
 end
 local short = label or prettifyItemId(idLog or "?")
 if #short > 22 then
 short = short:sub(1, 20) .. ".."
 end
 table.insert(recentCraftOrders, 1, {
 text = string.format("%s x%d", short, c),
 id = idLog,
 })
 while #recentCraftOrders > 5 do
 table.remove(recentCraftOrders)
 end
end

local function drainExportProgressFraction()
 if #pendingPostCraftExport == 0 then
 return nil
 end
 local num = 0
 local den = 0
 for _, q in ipairs(pendingPostCraftExport) do
 local tot = math.max(1, tonumber(q.totalNeed) or tonumber(q.stillNeed) or 1)
 local left = math.max(0, tonumber(q.stillNeed) or 0)
 local done = tot - left
 if done < 0 then
 done = 0
 end
 num = num + done
 den = den + tot
 end
 if den < 1 then
 return nil
 end
 return num / den
end

local function asciiProgressBar(frac, innerChars, tickForAnim)
 local iw = math.max(4, tonumber(innerChars) or 12)
 iw = math.min(iw, 32)
 local f = math.max(0, math.min(1, tonumber(frac) or 0))
 local fill = math.floor(f * iw + 0.5)
 if fill > iw then
 fill = iw
 end
 local t = math.max(0, tonumber(tickForAnim) or 0)
 local scanPos = (t % iw) + 1
 local segs = { "[" }
 for i = 1, iw do
 if i <= fill then
 table.insert(segs, "=")
 elseif tickForAnim ~= nil and fill < iw and i == scanPos then
 table.insert(segs, ">")
 else
 table.insert(segs, ".")
 end
 end
 table.insert(segs, "]")
 return table.concat(segs)
end

local function formatCraftJobsHud(tick)
 if #recentCraftOrders < 1 then
 return ""
 end
 local period = 16
 local t = math.max(0, tonumber(tick) or 0)
 if #recentCraftOrders == 1 then
 return "craft>" .. recentCraftOrders[1].text
 end
 local idx = (math.floor(t / period) % #recentCraftOrders) + 1
 return string.format("craft>%s %d/%d", recentCraftOrders[idx].text, idx, #recentCraftOrders)
end

local function buildCraftHudText(bridge, tick, maxLen)
 local busy = countBusyCraftingCpus(bridge)
 local pend = #pendingPostCraftExport
 local frac = drainExportProgressFraction()
 local spin = ""
 if showMeCraftingSpinner then
 spin = meCraftSpinChars[(math.max(0, tick) % 4) + 1] .. " "
 end
 local parts = {}
 local jobHud = formatCraftJobsHud(tick)
 if #jobHud > 0 then
 table.insert(parts, jobHud)
 end
 if busy > 0 then
 table.insert(parts, string.format("%sMEcpu:%d", spin, busy))
 end
 if frac then
 local barInner = math.min(14, math.max(6, math.floor((maxLen or 40) * 0.22)))
 table.insert(parts, asciiProgressBar(frac, barInner, tick) .. string.format("%d%%", math.floor(frac * 100 + 0.5)))
 elseif pend > 0 then
 table.insert(parts, "out q:" .. pend)
 end
 local s = table.concat(parts, " ")
 if #s > maxLen then
 s = s:sub(1, maxLen)
 end
 return s
end

local function meCraftingActivitySuffix(bridge, tick, useFullHudLine)
 if useFullHudLine then
 return ""
 end
 if not showMeCraftingStatus or not bridge then
 return ""
 end
 local busy = countBusyCraftingCpus(bridge)
 local pending = #pendingPostCraftExport
 if busy < 1 and pending < 1 then
 return ""
 end
 local spin = ""
 if showMeCraftingSpinner then
 local idx = (math.max(0, tick) % 4) + 1
 spin = meCraftSpinChars[idx] .. " "
 end
 return string.format("%sMEcpu:%d q:%d ", spin, busy, pending)
end

local function updateHeader(monitor, bridge, tick, snapshot)
 if not monitor then return end

 local width, height = monitor.getSize()
 local useCraftHud = showMeCraftingHudLine and height >= 8
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
 local suffix = meCraftingActivitySuffix(bridge, tick, useCraftHud)
 if #suffix > math.floor(width * 0.35) then
 suffix = ""
 end
 local maxLeft = width - #suffix - 4
 if maxLeft < 8 then
 suffix = ""
 maxLeft = math.floor(width * 0.58)
 end
 if #left > maxLeft then
 left = left:sub(1, math.max(0, maxLeft - 1))
 end
 monitor.setCursorPos(1, 2)
 monitor.setTextColor(colors.lightGray)
 monitor.write(left)
 local used = #left
 local midSpan = math.max(1, width - used - #suffix)
 local filled = math.floor((tick / scanInterval) * midSpan)
 monitor.setCursorPos(used + 1, 2)
 monitor.setTextColor(status and colors.green or colors.red)
 local hFill = math.min(filled, midSpan)
 monitor.write(string.rep("#", hFill))
 if midSpan > hFill then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", midSpan - hFill))
 end
 if #suffix > 0 then
 monitor.setTextColor(colors.yellow)
 monitor.write(suffix)
 end
 if useCraftHud then
 local hud = buildCraftHudText(bridge, tick, width)
 monitor.setCursorPos(1, 3)
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", width))
 monitor.setCursorPos(1, 3)
 monitor.setTextColor(colors.orange)
 monitor.write(hud)
 if #hud < width then
 monitor.setTextColor(colors.black)
 monitor.write(string.rep(" ", width - #hud))
 end
 end
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
 alarmInfo(result)
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
 local craftable = false
 local payload = {}
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
 local filter = buildMeItemFilter(name, fingerprintBridge, stackSize, comps)
 if filter then
 local okCr, cr = pcall(function()
 return bridge.isCraftable(filter)
 end)
 if okCr and cr then
 craftable = true
 payload = filter
 elseif not okCr and doLog then
 logLine("[ae2Colony] isCraftable error: " .. tostring(cr))
 end
 end
 if not craftable and meRegistryName(name) then
 local f2 = buildMeItemFilter(name, nil, stackSize, comps)
 if f2 then
 local okCr2, cr2 = pcall(function()
 return bridge.isCraftable(f2)
 end)
 if okCr2 and cr2 then
 craftable = true
 payload = f2
 end
 end
 end
 if craftable then
 local okInvoke, a, b = pcall(function()
 return bridge.craftItem(payload)
 end)
 if not okInvoke then
 logAndDisplay(
 string.format("[ERROR] craftItem threw: %s x%d %s (%s)", label, stackSize, idLog, tostring(a))
 )
 return false
 end
 if type(a) == "boolean" then
 if a then
 logAndDisplay(formatItemAction("[CRAFT]", stackSize, label, idLog, ""))
 pushRecentCraftOrder(label, idLog, stackSize)
 triggerAlert("craft_started")
 return true
 end
 logAndDisplay(
 string.format("[ERROR] Craft start failed: %s x%d %s — %s", label, stackSize, idLog, tostring(b or "?"))
 )
 return false
 end
 logAndDisplay(formatItemAction("[CRAFT]", stackSize, label, idLog, ""))
 pushRecentCraftOrder(label, idLog, stackSize)
 triggerAlert("craft_started")
 return true
 else
 logAndDisplay(formatItemAction("[MISSING] No recipe", stackSize, label, idLog, ""))
 notifyMissingPatternHook({
 name = name,
 count = stackSize,
 fingerprint = fingerprintRequest,
 target = (request and (request.target or request.name)) or "",
 display_label = label,
 })
 triggerAlert("missing_pattern")
 end
 return false
end

local function bridgeStockCountForNeed(bridge, entry)
 local comps = entry.components or {}
 local filter = buildMeItemFilter(entry.name, entry.fingerprint, 65536, comps)
 if not filter then
 return 0
 end
 local ok, it = pcall(function()
 return bridge.getItem(filter)
 end)
 if ok and it and type(it.count) == "number" then
 return it.count
 end
 return 0
end

local function postCraftDrainKey(entry)
 local fp = normalizeMeFingerprint(entry and entry.fingerprint)
 local nm = entry and entry.name or ""
 return tostring(fp or "") .. "|" .. tostring(nm)
end

local function enqueuePostCraftDrain(entry, stillNeed)
 if not constructionPushDrainAfterCraft or stillNeed < 1 or type(entry) ~= "table" then
 return
 end
 local now = os.epoch("utc")
 local deadline = now + (constructionPushDrainTimeoutSeconds or 180) * 1000
 local key = postCraftDrainKey(entry)
 for i = 1, #pendingPostCraftExport do
 local q = pendingPostCraftExport[i]
 if q.key == key then
 if stillNeed > q.stillNeed then
 q.stillNeed = stillNeed
 end
 q.totalNeed = math.max(tonumber(q.totalNeed) or 0, q.stillNeed)
 if deadline > q.deadlineMs then
 q.deadlineMs = deadline
 end
 return
 end
 end
 table.insert(pendingPostCraftExport, {
 key = key,
 name = entry.name,
 fingerprint = entry.fingerprint,
 components = entry.components or {},
 stillNeed = stillNeed,
 totalNeed = stillNeed,
 deadlineMs = deadline,
 label = entry.displayName or prettifyItemId(entry.name or "?"),
 idLog = entry.name or "?",
 })
end

local function processPendingPostCraftDrain(bridge)
 if not constructionPushDrainAfterCraft or #pendingPostCraftExport == 0 then
 return
 end
 if not bridge or not confirmConnection(bridge) then
 return
 end
 local now = os.epoch("utc")
 local pollMs = math.max(1, (constructionPushDrainPollSeconds or 1) * 1000)
 if now < lastPostCraftDrainMs + pollMs then
 return
 end
 lastPostCraftDrainMs = now
 local maxPer = math.max(1, constructionPushDrainMaxPerTick or 4)
 local processed = 0
 local i = 1
 while i <= #pendingPostCraftExport and processed < maxPer do
 local q = pendingPostCraftExport[i]
 local entry = {
 name = q.name,
 fingerprint = q.fingerprint,
 components = q.components,
 }
 if now > q.deadlineMs then
 logAndDisplay(
 string.format("[WARN] Post-craft export timeout: %s (%d left)", q.label or "?", q.stillNeed or 0)
 )
 triggerAlert("post_craft_timeout")
 table.remove(pendingPostCraftExport, i)
 else
 local stock = bridgeStockCountForNeed(bridge, entry)
 local move = math.min(stock, q.stillNeed)
 if move > 0 then
 queueExport(q.fingerprint, move, q.name, "work-order", nil, q.label, q.idLog, q.components)
 q.stillNeed = q.stillNeed - move
 end
 if q.stillNeed < 1 then
 table.remove(pendingPostCraftExport, i)
 else
 i = i + 1
 end
 end
 processed = processed + 1
 end
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
 refreshMonitorBody(monitor, bridge)
 end
 return
 end
 if not confirmConnection(bridge) then
 logAndDisplay("[MANUAL] AE2 offline; cannot craft/export.")
 return
 end
 logAndDisplay(string.format("[MANUAL] Footer push: %d material line(s)", #entries))
 for _, entry in ipairs(entries) do
 if tostring(entry.status or "") == "NOT_NEEDED" then
 else
 local need = math.floor(tonumber(entry.needed) or 0)
 if need < 1 then
 else
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
 local craftStarted = craftHandler(fakeReq, nil, bridge, remain, label, idLog)
 if constructionPushDrainAfterCraft and remain > 0 and craftStarted then
 enqueuePostCraftDrain(entry, remain)
 end
 end
 end
 end
 end
 lastPostCraftDrainMs = 0
 processPendingPostCraftDrain(bridge)
 processExportBuffer(bridge)
end

local function handleMonitorTouch(monitor, bridge, colony)
 while true do
 local event, side, x, y = os.pullEvent("monitor_touch")
 if side == peripheral.getName(monitor) then
 local w, h = monitor.getSize()
 if h >= 5 and y == h then
 local lay = footerAlertBarLayout(w)
 local hitTest = lay and lay.xTest and x >= lay.xTest
 local hitScan = lay and lay.xScan and (lay.scanW or 0) > 0 and x >= lay.xScan and x < lay.xTest
 local modeRight = (lay and (lay.xScan or lay.xTest)) or w
 local hitMode = lay and lay.modeW and lay.modeW > 0 and lay.xMode and x >= lay.xMode and x < modeRight
 if hitTest then
 playSpeakerTestBeep()
 elseif hitScan then
 scanSpeakersAndReport()
 elseif hitMode then
 if alerts.enabled then
 if alertsMuted then
 alerts.enabled = false
 alertsMuted = false
 saveAlertsMonitorOverride(false)
 saveAlertsMuted()
 else
 alertsMuted = true
 saveAlertsMuted()
 end
 else
 alerts.enabled = true
 alertsMuted = false
 saveAlertsMonitorOverride(true)
 saveAlertsMuted()
 end
 elseif showConstructionPushFooter and (not lay or x <= (lay.craftMax or w)) then
 manualConstructionPush(bridge, colony, monitor)
 else
 currentPage = currentPage + 1
 if currentPage > totalPages then
 currentPage = 1
 end
 end
 else
 currentPage = currentPage + 1
 if currentPage > totalPages then
 currentPage = 1
 end
 end
 refreshMonitorBody(monitor, bridge)
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
 logAndDisplay("[INFO] getRequests() is warehouse supply, not the build GUI list.")
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
if alerts.enabled then
 if alertsMuted then
 print("[ae2Colony] Alerts: ON (muted). Last line: tap [MUTED!] to turn alerts off, [TEST] for speaker beep.")
 else
 print("[ae2Colony] Alerts: ON — use a wired CC speaker. Last line: [TEST] = beep, tap [SND:ON] to mute.")
 end
else
 print("[ae2Colony] Alerts: OFF — set alerts.enabled in ae2colony_config.lua or tap [A:OFF] on the last line. [TEST] = speaker beep.")
 print("[ae2Colony] Optional file override (true/false): ae2colony_alerts_monitor_enabled.txt")
end
print("[ae2Colony] Autostart: keep startup.lua next to ae2Colony.lua (same wget folder). Monitors w>=16: last row [SCAN] lists speakers.")
if scada.enabled and uiMode == "scada" then
 print("[ae2Colony] SCADA layout on (experimental). Needs wide monitor; see docs/SCADA.md in repo.")
elseif scada.enabled then
 print("[ae2Colony] SCADA metrics on (set uiMode or ui.mode to scada + wide monitor for split view). docs/SCADA.md")
end

local function ae2MainLoop()
 local tick = scanInterval
 local nextUiMs = 0
 local prevUnderAttack = false
 local prevMeOnline = true
 while true do
 local nowMsLoop = os.epoch("utc")
 if scada.enabled and nowMsLoop >= nextScadaMs then
 scadaSnapshot = fetchScadaSnapshot(colony, bridge, nowMsLoop)
 nextScadaMs = nowMsLoop + math.max(5000, (tonumber(scada.intervalSec) or 15) * 1000)
 end
 exportBuffer = {}
 processPendingPostCraftDrain(bridge)
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
 local online = confirmConnection(bridge)
 if colonyUiSnapshot.breakerJustTripped then
 triggerAlert("get_buildings_breaker")
 colonyUiSnapshot.breakerJustTripped = false
 end
 if colonyUiSnapshot.underAttack and not prevUnderAttack then
 triggerAlert("raid")
 end
 if not online and prevMeOnline then
 triggerAlert("me_offline")
 end
 if online and not prevMeOnline then
 triggerAlert("me_online")
 end
 prevUnderAttack = colonyUiSnapshot.underAttack == true
 prevMeOnline = online
 mainHandler(bridge, colony)
 processExportBuffer(bridge)
 refreshMonitorBody(monitor, bridge)

 while tick > 0 do
 local now = os.epoch("utc")
 if scada.enabled and now >= nextScadaMs then
 scadaSnapshot = fetchScadaSnapshot(colony, bridge, now)
 nextScadaMs = now + math.max(5000, (tonumber(scada.intervalSec) or 15) * 1000)
 end
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
 refreshMonitorBody(monitor, bridge)
 end
 local online = confirmConnection(bridge)
 if colonyUiSnapshot.breakerJustTripped then
 triggerAlert("get_buildings_breaker")
 colonyUiSnapshot.breakerJustTripped = false
 end
 if colonyUiSnapshot.underAttack and not prevUnderAttack then
 triggerAlert("raid")
 end
 if not online and prevMeOnline then
 triggerAlert("me_offline")
 end
 if online and not prevMeOnline then
 triggerAlert("me_online")
 end
 prevUnderAttack = colonyUiSnapshot.underAttack == true
 prevMeOnline = online
 if online then
 tick = tick - 1
 end
 processPendingPostCraftDrain(bridge)
 if #exportBuffer > 0 then
 processExportBuffer(bridge)
 end
 updateHeader(monitor, bridge, tick, colonyUiSnapshot)
 os.sleep(1)
 end
 tick = scanInterval
 end
end

local function ae2TouchLoop()
 handleMonitorTouch(monitor, bridge, colony)
end

parallel.waitForAll(ae2MainLoop, ae2TouchLoop)
