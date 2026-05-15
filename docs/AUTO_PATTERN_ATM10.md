# Auto-patterns on ATM10 (AE2 + Extended AE + ComputerCraft)

## What is actually impossible from `ae2Colony.lua` alone

ComputerCraft’s `me_bridge` (Advanced Peripherals) can **list storage**, **export items**, and **start crafts** (`isCraftable` / `craftItem`). It does **not** expose an API to:

- encode a new **AE2 crafting / processing / stonecutting / smithing** pattern, or  
- push that encoded pattern into an **Extended AE Assembly Matrix** slot.

Extended AE’s **Assembly Matrix Upload Core** (from **ExtendedAE-Plus**) speeds up **in-game** pattern uploads from terminals; it is still a **player-driven / UI-driven** flow, not a Lua peripheral API.

So: **“if no recipe, auto-create pattern in the matrix”** cannot be implemented *only* inside the CC script without extra software on the server.

## Practical approaches (pick one)

### A) Recommended: pre-seed patterns + script only crafts/exports

For MineColonies construction spam (stone tools, planks, glass, etc.), bulk-add patterns once (JEI fill, or ExtendedAE-Plus upload into the matrix). The script then stops showing `[MISSING]` for those ids.

### B) This repo: **missing-pattern webhook + JSONL log** (v0.4.3+)

In `ae2Colony.lua`, set:

```lua
local missingPatternHook = {
  enabled = true,
  httpUrl = "http://127.0.0.1:8099/ae2colony/missing",
  httpSecret = "change-me", -- optional; must match AE2COLONY_HOOK_SECRET on the receiver
  cooldownSeconds = 120,
  logFile = "ae2colony_missing_patterns.jsonl",
}
```

On the **same Windows machine that runs the Minecraft server**, run the small receiver from `pattern-hook/` (see `pattern-hook/README.md`). Each `[MISSING]` line in-game becomes one JSON line you can feed into **your own** automation (Discord webhook, admin ping, or a future custom mod).

**Requirements:** CC `http` must be allowed (`http` enabled for computers in `computercraft-server.toml`). The URL must be reachable **from the Minecraft server process** (`127.0.0.1` if the hook runs on the same host).

### C) Heavyweight but “real” automation: custom NeoForge mod + peripheral

If you want true **encode + insert** without clicking: a tiny server-side mod could call AE2 / Extended AE **Java APIs** from a block or command. That is outside this Lua repo but is the only fully automatic path that scales.

### D) Applied KubeJS (already common in ATM10-style packs)

[Applied KubeJS](https://kubejs.com/wiki/addons/applied-kjs) is great for **AE2 recipe JSON**, grid events, and (optionally) scripted craft **plans** — it still does **not** replace “encode GUI pattern → matrix slot” as a one-liner from ComputerCraft. Use it together with (B) if you later add Java-side pattern encoding.

## Optional in-game reminder command

See `extras/kubejs/README.md` — a tiny `/ae2colony_missing …` helper you can copy into your server’s `kubejs/server_scripts/` if you want ops to broadcast “encode this id” without reading JSONL.
