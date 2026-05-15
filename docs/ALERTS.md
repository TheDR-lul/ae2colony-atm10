# Alerts, pinned lines, and NEEDS diff (v0.5.12+)

## Pinned `[ALERT]` rows

When the ME bridge is offline, the colony is under attack, or the `getBuildings` API circuit breaker is active, the script prepends up to **`pinnedAlertsMaxLines`** rows (default **3**) at the **top of the monitor body** (before grouped COLONY / NEEDS / …). Colors: red for raid / ME offline, orange for the buildings API breaker.

## Sound and redstone

Set in `ae2colony_config.lua` (see `ae2colony_config.example.lua`):

- **`alerts.enabled`** — master switch (default `false`).
- **`alerts.minIntervalSec`** — minimum seconds between alerts of the **same kind** (debounce).
- **`alerts.useSpeaker`** — play short note patterns on a **ComputerCraft speaker** (`peripheral.find("speaker")` or **`alerts.speakerPeripheralName`**).
- **`alerts.useRedstone`** — pulse **`alerts.redstoneSide`** (e.g. note block, bell, lamp) for each alert; **`alerts.redstonePulseTicks`** controls pulse length.

Per-event toggles: `onRaid`, `onMeOffline`, `onMeOnline`, `onMissingPattern`, `onPostCraftTimeout`, `onGetBuildingsBreaker`, `onColonyRequestsCritical`, `onCraftStarted` (all default as in the example file).

**Speaker API:** uses `playNote(instrument, volume, pitch)` with `pcall` so unknown instruments fail quietly. Adjust instruments in the script if your CC version differs.

## NEEDS diff

When **`showConstructionNeedsDiff = true`**, the script prepends up to **`constructionNeedsDiffMaxLines`** lines showing changes since the last colony UI refresh: `[NEEDS] +`, `[NEEDS] -`, `[NEEDS] ~` (quantity or status change). Keys are fingerprint + item name + work order id.

## Colony summary

When work-order NEEDS are listed, an extra **`[COLONY] Blocking: N DONT_HAVE (of M listed)`** line helps see how many rows are still blocking progress.
