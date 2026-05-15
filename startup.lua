-- Autostart AE2 Colony on computer boot (place next to ae2Colony.lua).
if fs.exists("ae2Colony.lua") then
 shell.run("ae2Colony")
else
 print("startup.lua: ae2Colony.lua not found — wget it from the repo first.")
end
