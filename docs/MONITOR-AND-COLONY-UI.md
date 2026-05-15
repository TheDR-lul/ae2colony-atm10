# Monitor layout and colony UI (v0.5.0+; NEEDS footer from **v0.5.1**)

## Two install URLs

| Track | URL |
|--------|-----|
| **Latest** (current `main`) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua` |
| **Frozen v0.4.6** (before colony UI / config merge) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/releases/ae2Colony-v0.4.6.lua` |

## Row layout (monitor)

1. **Line 1:** Script name + version, page hint, AE2 ONLINE/OFFLINE.
2. **Line 2:** **Colony strip** (name, construction sites count, citizens, happiness) in gray, then a **green/red progress bar** for time until the next ME/colony scan (same meaning as before v0.5.0).
3. **Lines 3 … (height−1):** Grouped messages (COLONY, **NEEDS**, WARN, ERROR, MISSING, CRAFT, SENT, …). If the monitor is at least **5** lines tall and `showConstructionPushFooter` is on, the **last line** is reserved for the footer (not part of the scrollable page math).
4. **Last line (v0.5.1+, monitor height ≥ 5):** yellow **`>>> CRAFT+EXPORT (NEEDS) <<<`**. Tap that line (not a right-click elsewhere) to run a **one-shot** pass: for each row in **NEEDS**, export whatever is already in ME, then queue autocraft for the remainder (same checks as the main loop: no recipe → `[MISSING]`, partial stock → export partial + craft rest). The script **re-fetches** work-order resources on tap so the list is not stale.

**Direct delivery to builders:** ComputerCraft / Advanced Peripherals cannot target a citizen’s inventory. Materials must go through your **export chest** next to the ME bridge; MineColonies couriers/ builders pull from colony logistics as usual.

## What “construction progress” means here

MineColonies + Advanced Peripherals **do not** expose a single “% of blocks placed” value for arbitrary huts.

The script shows:

- **Light stats** (every `colonyUiInterval` seconds, default 5): colony name, `amountOfConstructionSites`, citizens vs max, happiness, under-attack flag.
- **Work orders** (if `showConstructionDetail`, default on): up to **3** highest-priority work orders with building name, target level, claimed flag, plus **one** summary line of top resource from the highest-priority order.
- **NEEDS list** (if `showConstructionNeedsList`, default on): merged from `getWorkOrderResources` for the top **N** work orders **plus** (if `mergeBuilderHutResources`, default on) **`getBuilderResources({x,y,z})`** at each order’s `builder` position — this second call usually matches the **in-game “Required resources”** list better than `getRequests()`.
- **Buildings list** (if `showBuildingsList`, default **off**): up to **2** entries where `built == false` or `isWorkingOn`. If `getBuildings()` errors (known issue on some MineColonies builds), the script trips a **circuit breaker** and disables that call for `buildingsBreakerMinutes` (default 30).

`getRequests()` is **only** the colony’s open **warehouse / delivery** request lines. **Construction “Required resources”** in the MineColonies GUI comes from **work orders** / **builder hut** data — that is why the script can show a full **NEEDS** block while `== INFO ==` still says no `getRequests()` lines.

## Configuration file

Optional `ae2colony_config.lua` next to the script. Copy from [`ae2colony_config.example.lua`](../ae2colony_config.example.lua). On success you will see `[ae2Colony] Merged ae2colony_config.lua` in the computer terminal at startup.

## Group order and caps

`monitorGroupOrder` controls section order. `maxLinesPerGroup` caps entries per section; overflow shows `...+N more`.

## Manual test checklist

1. **Latest script:** `wget run` the `main/ae2Colony.lua` URL, run `ae2Colony`, confirm version **0.5.2-atm10** (or newer) on line 1.
2. **Stable frozen:** `wget run` the `releases/ae2Colony-v0.4.6.lua` URL — version **0.4.6-atm10**, no COLONY block in grouped list.
3. **Monitor sizes:** try 4-wide and 8-wide monitors; header and colony strip must not overlap status text; page flip still works.
4. **Colony strip:** with an active build, COLONY lines appear; with no builds, strip may show only name + stats.
5. **`showBuildingsList = true`:** if server stays up and no `[WARN] getBuildings disabled` appears, API is compatible; if warn appears, breaker engaged — wait 30m or lower `buildingsBreakerMinutes` in config for testing.
6. **Regression:** `[SENT]` / ledger file / partial craft + remainder craft still behave as in v0.4.6.
7. **NEEDS + footer:** With an active build order, `== NEEDS ==` lists materials; tap the bottom **CRAFT+EXPORT** line — expect `[MANUAL]` summary, then `[SENT]` / `[CRAFT]` / `[MISSING]` lines as appropriate. Tapping above the footer still cycles pages.
