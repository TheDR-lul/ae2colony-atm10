# Optional KubeJS helper (ATM10 / NeoForge)

Copy `ae2colony_missing_command.js` into your **server** folder:

`<server root>/kubejs/server_scripts/ae2colony_missing_command.js`

Then reload scripts or restart the server.

## What it does

Adds `/ae2colony_missing <item_id>` — prints a yellow server-wide notice so operators remember to encode that item in an ME Pattern Encoding Terminal and upload to your Extended AE Assembly Matrix (or pattern provider chain).

It does **not** create encoded patterns automatically.

## Permissions

Restrict `/ae2colony_missing` with your pack’s command permissions (LuckPerms, FTB Ranks, etc.). The script itself does not enforce ops-only checks.
