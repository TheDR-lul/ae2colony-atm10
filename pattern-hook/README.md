# ae2Colony pattern hook (optional)

Small HTTP receiver for the **missing AE autocraft recipe** webhook from `ae2Colony.lua` v0.4.3+.

## Why

ComputerCraft cannot create AE2 encoded patterns. This process **logs** each missing `item_id` so you can wire your own follow-up (Discord, RCON broadcast, manual list, etc.).

## Run (same PC as the Minecraft server)

```bash
cd pattern-hook
set AE2COLONY_HOOK_SECRET=change-me
python server.py
```

Default listen: `http://127.0.0.1:8099/ae2colony/missing`

In `ae2Colony.lua`:

```lua
local missingPatternHook = {
  enabled = true,
  httpUrl = "http://127.0.0.1:8099/ae2colony/missing",
  httpSecret = "change-me",
  cooldownSeconds = 120,
  logFile = "ae2colony_missing_patterns.jsonl",
}
```

## Files written

- `missing_patterns_queue.jsonl` — one JSON object per POST (append-only)

## Security

- Bind to `127.0.0.1` only (default).
- Always set `AE2COLONY_HOOK_SECRET` and the same value in `httpSecret` in Lua.

## CC server config

In `computercraft-server.toml` (or equivalent), ensure computers may use HTTP to local addresses if your pack disables it by default.
