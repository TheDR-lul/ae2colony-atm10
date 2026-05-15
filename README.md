# ae2colony-atm10

Public fork of [toastonrye/ae2Colony](https://github.com/toastonrye/ae2Colony) for **CC: Tweaked**, **Applied Energistics 2**, and **MineColonies**, with a relaxed **Advanced Peripherals** version check so current **ATM10** builds (e.g. AP 0.7.59b+) can run the script.

Upstream is MIT-licensed; see [LICENSE](LICENSE).

**Russian “press the button” setup (chest on ME bridge, colony build):** [docs/SIMPLE-RU.md](docs/SIMPLE-RU.md)  
**v0.4.6:** export ledger (no double-pull from ME while colony count lags), human-readable names on monitor, partial-export craft uses remainder only.

## Install (in-game computer)

```text
wget run https://raw.githubusercontent.com/TheDR-lul/ae2colony-atm10/main/ae2Colony.lua
```

Then run:

```text
ae2Colony
```

(Optional) Save as `startup.lua` with `shell.run("ae2Colony")` for autostart.

## Missing AE patterns (ATM10 / Extended AE)

ComputerCraft cannot encode AE2 patterns or push them into an **Extended AE Assembly Matrix** by itself. v**0.4.3** can **log + HTTP POST** each `[MISSING]` item so you can wire your own server-side follow-up:

- Read [`docs/AUTO_PATTERN_ATM10.md`](docs/AUTO_PATTERN_ATM10.md)
- Optional receiver: [`pattern-hook/README.md`](pattern-hook/README.md)

Enable in `ae2Colony.lua` → table `missingPatternHook` (`enabled = true`, `httpUrl`, optional `httpSecret`, `logFile`).

## Requirements

- CC: Tweaked, Advanced Peripherals (with `me_bridge` + `colony_integrator`), AE2, MineColonies — see upstream README for setup details.

## Note

The original author may stop maintaining the script; this repo only hosts a small compatibility fork for newer ATM10.
