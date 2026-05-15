# Monitor layout and colony UI (v0.5.0+)

## Two install URLs

| Track | URL |
|--------|-----|
| **Latest** (current `main`) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua` |
| **Frozen v0.4.6** (before colony UI / config merge) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/releases/ae2Colony-v0.4.6.lua` |

## Row layout (monitor)

1. **Line 1:** Script name + version, page hint, AE2 ONLINE/OFFLINE.
2. **Line 2:** **Colony strip** (name, construction sites count, citizens, happiness) in gray, then a **green/red progress bar** for time until the next ME/colony scan (same meaning as before v0.5.0).
3. **Lines 3+:** Grouped messages (COLONY, WARN, ERROR, MISSING, CRAFT, SENT, …).

## What “construction progress” means here

MineColonies + Advanced Peripherals **do not** expose a single “% of blocks placed” value for arbitrary huts.

The script shows:

- **Light stats** (every `colonyUiInterval` seconds, default 5): colony name, `amountOfConstructionSites`, citizens vs max, happiness, under-attack flag.
- **Work orders** (if `showConstructionDetail`, default on): up to **3** highest-priority work orders with building name, target level, claimed flag, plus **one** line of top resource need from `getWorkOrderResources` for the top order only (to limit server load).
- **Buildings list** (if `showBuildingsList`, default **off**): up to **2** entries where `built == false` or `isWorkingOn`. If `getBuildings()` errors (known issue on some MineColonies builds), the script trips a **circuit breaker** and disables that call for `buildingsBreakerMinutes` (default 30).

There is **no exact block-%** in this UI by design.

## Configuration file

Optional `ae2colony_config.lua` next to the script. Copy from [`ae2colony_config.example.lua`](../ae2colony_config.example.lua). On success you will see `[ae2Colony] Merged ae2colony_config.lua` in the computer terminal at startup.

## Group order and caps

`monitorGroupOrder` controls section order. `maxLinesPerGroup` caps entries per section; overflow shows `...+N more`.

## Manual test checklist

1. **Latest script:** `wget run` the `main/ae2Colony.lua` URL, run `ae2Colony`, confirm version **0.5.0-atm10** on line 1.
2. **Stable frozen:** `wget run` the `releases/ae2Colony-v0.4.6.lua` URL — version **0.4.6-atm10**, no COLONY block in grouped list.
3. **Monitor sizes:** try 4-wide and 8-wide monitors; header and colony strip must not overlap status text; page flip still works.
4. **Colony strip:** with an active build, COLONY lines appear; with no builds, strip may show only name + stats.
5. **`showBuildingsList = true`:** if server stays up and no `[WARN] getBuildings disabled` appears, API is compatible; if warn appears, breaker engaged — wait 30m or lower `buildingsBreakerMinutes` in config for testing.
6. **Regression:** `[SENT]` / ledger file / partial craft + remainder craft still behave as in v0.4.6.
