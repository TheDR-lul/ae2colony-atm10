// Copy to: <server>/kubejs/server_scripts/ae2colony_missing_command.js
// Optional helper — does NOT create AE2 patterns automatically.
// Restrict with LuckPerms / FTB Ranks / your pack's command permissions.

ServerEvents.basicCommand("ae2colony_missing", (event) => {
  const input = (event.input || "").trim();
  if (!input) {
    event.player.tell(Text.red("Usage: /ae2colony_missing <item_id>"));
    return;
  }

  const msg = `[ae2Colony] Encode AE pattern for: ${input} (ME terminal → pattern → Assembly Matrix / providers)`;
  event.server.tell(Text.yellow(msg));
});
