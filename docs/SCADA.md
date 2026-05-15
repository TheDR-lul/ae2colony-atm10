# SCADA-style monitor (experimental, v0.6.0+)

Split monitor layout: left column keeps the usual grouped colony/NEEDS log; right column shows citizen food **saturation** (from `colony.getCitizens()`), ME counts for a small **whitelist**, and a **heuristic** saturation trend (not a game prediction).

## Enable

In `ae2colony_config.lua` return table, set for example:

```lua
  uiMode = "scada", -- or: ui = { mode = "scada" },
  scada = {
    enabled = true,
    intervalSec = 15,
    minMonitorWidth = 26,
    leftBodyFraction = 0.58,
    saturationWarnBelow = 8,
    scanMeFoodFromWhitelist = true,
    foodWhitelist = { "minecraft:bread", "minecraft:cooked_beef" },
    historyFile = "ae2colony_scada_history.jsonl",
    historySampleSec = 60,
    maxHistoryPoints = 48,
    trendWindowPoints = 10,
    warnTrendDropCycles = 3,
  },
```

If the monitor is narrower than `minMonitorWidth`, the script falls back to **classic** full-width body (no split).

## Data sources

- **Citizens:** `getCitizens()` via Advanced Peripherals colony integrator. Field used: `saturation` (name may vary slightly by AP/MineColonies version; script tolerates missing numbers).
- **ME food:** `me_bridge.getItem` per entry in `foodWhitelist` (cheap). Do **not** rely on full `getItems()` here.
- **Trend:** each `historySampleSec`, one line is appended to `historyFile` with `textutils.serialize`. A simple linear slope over the last `trendWindowPoints` samples drives `est.sat/step` and optional `[WARN] sat trend down`.

## Verify in your pack (ATM10)

Once in-game, open the computer terminal after boot and confirm no `getCitizens` errors. If saturation is always missing, check AP docs for your exact version and report the citizen table shape.
