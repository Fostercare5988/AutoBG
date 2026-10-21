# AutoBG

Battleground helper: queueing and auto-enter, objective timers, flag carriers,
enemy frames and the Spy enemy list. Player guide: `docs/USER_GUIDE.md`.
Regression tests: `regressions/AutoBG` in VanillaForge (98 tests).

| File | Job |
| --- | --- |
| `ForgeUI.lua` | The shared settings kit (ForgeUI) |
| `AutoBG.lua` | Settings and defaults, queue pops and auto-enter, match end, auto-rejoin, `/abg` commands |
| `AutoBG_Timers.lua` | Base and node countdowns, match start, spirit healer waves, queue times, Arathi Basin projection |
| `AutoBG_FC.lua` | Warsong Gulch flag carrier frames |
| `AutoBG_Targets.lua` | Enemy frames: health, cast bars, range fading, raid icons, trinkets, stealth |
| `AutoBG_Spy.lua` | Enemy list and stealth alerts outside battlegrounds |
| `AutoBG_Options.lua` | Settings window, tabs General, Timers, Enemy frames, Spy |

Things to know:

- Enemy frames have separate sizes and positions per battleground size
  (10, 15, 40). In a match the settings page edits the size being played.
- OctoWoW invites run out after about 80 seconds. Auto-enter goes in 5 seconds
  before that (the delay setting tops out at 75), and learns a shorter window
  from an invite that runs out (`AutoBG_Settings.InviteWindow`).
- Faction colors on timers and the Arathi Basin projection are always on; their
  old settings are cleared on load.
