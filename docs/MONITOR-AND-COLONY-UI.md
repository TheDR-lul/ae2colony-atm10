# Monitor layout and colony UI (v0.5.0+; NEEDS footer from **v0.5.1**)

## Two install URLs

| Track | URL |
|--------|-----|
| **Latest** (current `main`) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua` |
| **Frozen v0.4.6** (before colony UI / config merge) | `https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/releases/ae2Colony-v0.4.6.lua` |

## Row layout (monitor)

1. **Line 1:** Script name + version, page hint, AE2 ONLINE/OFFLINE.
2. **Line 2:** **Colony strip** (name, construction sites count, citizens, happiness) in gray, then a **green/red progress bar** for time until the next ME/colony scan (same meaning as before v0.5.0).
3. **Lines 3 … (height−1):** Grouped messages (COLONY, **NEEDS**, WARN, ERROR, MISSING, CRAFT, SENT, …). From **v0.5.12**, up to **`pinnedAlertsMaxLines`** **`[ALERT]`** rows (red/orange) are **prepended** above the grouped sections when the ME bridge is offline, the colony is under attack, or the `getBuildings` API breaker is active — see [ALERTS.md](ALERTS.md). If `showMeCraftingHudLine` is on and the monitor is at least **8** lines tall, **line 3** is reserved for the **craft HUD** (export progress / recent crafts); grouped content starts below it.
4. **Last line (v0.5.1+, monitor height ≥ 5):** yellow **`>>> CRAFT+EXPORT (NEEDS) <<<`**. Tap that line (not a right-click elsewhere) to run a **one-shot** pass: for each row in **NEEDS**, export whatever is already in ME, then queue autocraft for the remainder (same checks as the main loop: no recipe → `[MISSING]`, partial stock → export partial + craft rest). The script **re-fetches** work-order resources on tap so the list is not stale. The footer is **not** part of the scrollable page count (same as pre–v0.5.12).

Optional **`showConstructionNeedsDiff`**: prepends `[NEEDS] +` / `-` / `~` lines when the merged list changes between colony UI refreshes — see [ALERTS.md](ALERTS.md).

**Direct delivery to builders:** ComputerCraft / Advanced Peripherals cannot target a citizen’s inventory. Materials must go through your **export chest** next to the ME bridge; MineColonies couriers/ builders pull from colony logistics as usual.

## What “construction progress” means here

MineColonies + Advanced Peripherals **do not** expose a single “% of blocks placed” value for arbitrary huts.

The script shows:

- **Light stats** (every `colonyUiInterval` seconds, default 5): colony name, `amountOfConstructionSites`, citizens vs max, happiness, under-attack flag.
- **Work orders** (if `showConstructionDetail`, default on): up to **3** highest-priority work orders with building name, target level, claimed flag, plus **`[COLONY] Top need`** — the same row as the first line in **NEEDS** after merge/sort (**v0.5.5+**; quantities aligned with **v0.5.6+**). From **v0.5.12**, when NEEDS are listed, **`[COLONY] Blocking: N DONT_HAVE (of M listed)`** counts how many rows are still in `DONT_HAVE`.
- **NEEDS list** … **v0.5.6:** quantities prefer **`amount` − `amountAvailable`** (MineColonies `BuildingBuilderResource`) when the API exposes both, falling back to `needed` / other fields. Lines may show **`(30/48)`** next to the deficit count so you can compare with the in-game list. **CRAFT+EXPORT** uses that same deficit for export + craft.
- **Buildings list** (if `showBuildingsList`, default **off**): up to **2** entries where `built == false` or `isWorkingOn`. If `getBuildings()` errors (known issue on some MineColonies builds), the script trips a **circuit breaker** and disables that call for `buildingsBreakerMinutes` (default 30).

`getRequests()` is **only** the colony’s open **warehouse / delivery** request lines. **Construction “Required resources”** in the MineColonies GUI comes from **work orders** / **builder hut** data — that is why the script can show a full **NEEDS** block while `== INFO ==` still says no `getRequests()` lines. If **NEEDS** was empty while **COLONY / Top need** showed a line, older builds used `#res` (Lua length) on a sparse resource table — **v0.5.3** walks all numeric keys and unwraps `item` tables. If the computer crashes with **“Generic filter requires either field type or name”**, update to **v0.5.4+** (stricter `me_bridge` filters).

## Configuration file

Optional `ae2colony_config.lua` next to the script. Copy from [`ae2colony_config.example.lua`](../ae2colony_config.example.lua). On success you will see `[ae2Colony] Merged ae2colony_config.lua` in the computer terminal at startup.

## Group order and caps

`monitorGroupOrder` controls section order. `maxLinesPerGroup` caps entries per section; overflow shows `...+N more`.

## Manual test checklist

1. **Latest script:** `wget run` the `main/ae2Colony.lua` URL, run `ae2Colony`, confirm version **0.5.6-atm10** (or newer) on line 1.
2. **Stable frozen:** `wget run` the `releases/ae2Colony-v0.4.6.lua` URL — version **0.4.6-atm10**, no COLONY block in grouped list.
3. **Monitor sizes:** try 4-wide and 8-wide monitors; header and colony strip must not overlap status text; page flip still works.
4. **Colony strip:** with an active build, COLONY lines appear; with no builds, strip may show only name + stats.
5. **`showBuildingsList = true`:** if server stays up and no `[WARN] getBuildings disabled` appears, API is compatible; if warn appears, breaker engaged — wait 30m or lower `buildingsBreakerMinutes` in config for testing.
6. **Regression:** `[SENT]` / ledger file / partial craft + remainder craft still behave as in v0.4.6.
7. **NEEDS + footer:** With an active build order, `== NEEDS ==` lists materials; tap the bottom **CRAFT+EXPORT** line — expect `[MANUAL]` summary, then `[SENT]` / `[CRAFT]` / `[MISSING]` lines as appropriate. Tapping above the footer still cycles pages.
8. **Counts (v0.5.5+):** `[COLONY] Top need` item name, quantity, and status match the first `[NEEDS]` line; `NOT_NEEDED` rows should not appear unless `constructionNeedsHideNotNeeded = false`.
9. **Quantities (v0.5.6+):** compare NEEDS `xN` and optional `(a/t)` suffix with the MineColonies “Required resources” screen; footer **CRAFT+EXPORT** should request craft for the same deficit `N` (minus what ME already has in stock).
