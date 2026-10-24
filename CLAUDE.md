# AutoBG

Battleground helper: queueing and auto-enter, objective timers, flag carriers,
enemy frames and the Spy enemy list. Player guide: `docs/USER_GUIDE.md`.
Regression tests: `regressions/AutoBG` in VanillaForge (129 tests).

| File | Job |
| --- | --- |
| `ForgeUI.lua` | The shared settings kit (ForgeUI) |
| `AutoBG.lua` | Settings and defaults, queue pops and auto-enter, match end, auto-rejoin, `/abg` commands |
| `AutoBG_Timers.lua` | Base and node countdowns, match start, spirit healer waves, queue times, Arathi Basin projection |
| `AutoBG_FC.lua` | Warsong Gulch flag carrier frames |
| `AutoBG_Targets.lua` | Enemy frames: health, cast bars, range fading, raid icons, trinkets, stealth |
| `AutoBG_Spy.lua` | Enemy list and stealth alerts outside battlegrounds |
| `AutoBG_FlagWatch.lua` | AB/AV warning when a visible enemy stands still at a flag; learns flag spots per map (`AutoBG_Settings.FlagSpots`) |
| `AutoBG_Options.lua` | Settings window, tabs General, Timers, Enemy frames, Spy |

Things to know:

- Enemy frames have separate sizes and positions per battleground size
  (10, 15, 40). In a match the settings page edits the size being played.
- OctoWoW invites run out after about 80 seconds. Auto-enter goes in at 79 seconds
  at the latest (the delay setting tops out at 79). Dynamic invite window is retired.
- Faction colors on timers and the Arathi Basin projection are always on; their
  old settings are cleared on load.
- A cast started from stealth never reaches the client (the caster is still
  invisible), so the flag watch uses positions, not cast bars.
