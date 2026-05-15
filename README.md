# ae2colony-atm10

Public fork of [toastonrye/ae2Colony](https://github.com/toastonrye/ae2Colony) for **CC: Tweaked**, **Applied Energistics 2**, and **MineColonies**, with a relaxed **Advanced Peripherals** version check so current **ATM10** builds (e.g. AP 0.7.59b+) can run the script.

Upstream is MIT-licensed; see [LICENSE](LICENSE).

**Russian “press the button” setup:** [docs/SIMPLE-RU.md](docs/SIMPLE-RU.md)  
**Monitor + colony UI + config (v0.5.0+):** [docs/MONITOR-AND-COLONY-UI.md](docs/MONITOR-AND-COLONY-UI.md)  
**Alerts, pinned lines, NEEDS diff (v0.5.12+):** [docs/ALERTS.md](docs/ALERTS.md)  
**Optional config template:** [ae2colony_config.example.lua](ae2colony_config.example.lua) (copy to `ae2colony_config.lua` on the computer)

## Install tracks

| Track | Command |
|--------|---------|
| **Latest** (`main`, recommended for new features) | `wget run https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua` |
| **Frozen v0.4.6** (no colony UI strip / no external config merge) | `wget run https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/releases/ae2Colony-v0.4.6.lua` |

Then run:

```text
ae2Colony
```

(Optional) Save as `startup.lua` with `shell.run("ae2Colony")` for autostart.

### v0.5.12 highlights

- **Pinned `[ALERT]` rows** at the top of the monitor when ME is offline, the colony is under attack, or the `getBuildings` API breaker is active.
- **Optional speaker + redstone** alerts (debounced) for raid, ME offline/online, missing patterns, post-craft export timeout, `getRequests` critical failure, and more — see [docs/ALERTS.md](docs/ALERTS.md).
- **Optional NEEDS diff** (`showConstructionNeedsDiff`): `+` / `-` / `~` lines when the merged material list changes.
- **`[COLONY] Blocking:`** summary: count of `DONT_HAVE` rows among listed NEEDS.

### v0.5.6 highlights

- **NEEDS quantities:** prefer MineColonies-style **`amount` − `amountAvailable`** (delivered vs required) when both exist, so monitor matches the build GUI deficit; suffix **`(avail/total)`** on lines. Footer push skips `NOT_NEEDED` and zero-need rows; craft/export uses the same **needed** value.

### v0.5.5 highlights

- **NEEDS vs Top need:** one merged list; `Top need` = first row after sort. Duplicate WO+builder counts use **`max`**; **`NOT_NEEDED`** hidden by default.

### v0.5.4 highlights

- **me_bridge filters:** newer Advanced Peripherals reject `getItem` / `isCraftable` / `exportItem` filters that only have `fingerprint` without a registry **`name`** (`mod:id`). The script now builds filters via `buildMeItemFilter` and wraps `isCraftable` in `pcall` so one bad row does not crash the computer.

### v0.5.3 highlights

- **NEEDS parsing:** tolerate sparse / non-array `getWorkOrderResources` / `getBuilderResources` tables and nested `item` objects (fixes empty NEEDS while “Top need” still showed).

### v0.5.2 highlights

- **NEEDS** also merges **`getBuilderResources`** at the builder hut position (closer to the MineColonies “Required resources” UI than `getRequests()` alone).
- Clearer **INFO** when `getRequests()` is empty: warehouse requests are not the same as construction materials.

### v0.5.1 highlights

- **`== NEEDS ==` window:** merged construction materials from active work orders (`getWorkOrderResources`).
- **Footer `CRAFT+EXPORT`:** tap bottom line (monitor ≥5 lines tall) to export in-stock items and queue autocraft for the rest; re-fetches colony data on tap.

### v0.5.0 highlights

- Colony stats + work-order summary on the monitor (no exact block-% — see docs).
- Optional `ae2colony_config.lua` overrides without editing the main script.
- `getBuildings` optional, off by default, with circuit breaker on API errors.
- Group order + per-group line caps on the monitor.

v**0.4.6** (stable file): export ledger, readable item labels, partial-export craft remainder, default ME export `top`.

## Missing AE patterns (ATM10 / Extended AE)

ComputerCraft cannot encode AE2 patterns or push them into an **Extended AE Assembly Matrix** by itself. The script can **log + HTTP POST** each `[MISSING]` item — see [docs/AUTO_PATTERN_ATM10.md](docs/AUTO_PATTERN_ATM10.md) and [pattern-hook/README.md](pattern-hook/README.md).

## Requirements

- CC: Tweaked, Advanced Peripherals (`me_bridge` + `colony_integrator`), AE2, MineColonies — see upstream README for setup details.

## Note

The original author may stop maintaining the script; this repo only hosts a small compatibility fork for newer ATM10.
