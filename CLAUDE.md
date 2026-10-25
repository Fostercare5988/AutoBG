# AutoBG

Battleground helper: queueing and auto-enter, objective timers, flag carriers,
enemy frames and the Spy enemy list. Player guide: `docs/USER_GUIDE.md`.
Regression tests: `regressions/AutoBG` in VanillaForge (148 tests).

| File | Job |
| --- | --- |
| `ForgeUI.lua` | The shared settings kit (ForgeUI) |
| `AutoBG.lua` | Settings and defaults, queue pops and auto-enter, match end, auto-rejoin, `/abg` commands |
| `AutoBG_Timers.lua` | Base and node countdowns, match start, spirit healer waves, queue times, Arathi Basin projection |
| `AutoBG_FC.lua` | Warsong Gulch flag carrier frames |
| `AutoBG_Targets.lua` | Enemy frames: health, cast bars, range fading, raid icons, trinkets, stealth |
| `AutoBG_AlertCard.lua` | The popup card kit (`ns.CreateAlertCard`); the stealth and flag warnings each own one |
| `AutoBG_Spy.lua` | Enemy list and stealth alerts outside battlegrounds; off in raids by default |
| `AutoBG_FlagAlert.lua` | The flag warning card, Ctrl+click announce; learns the Opening spell (`AutoBG_Settings.OpeningSpell`) |
| `AutoBG_FlagWatch.lua` | AB/AV watch: a visible enemy standing still at a flag; learns flag spots per map (`AutoBG_Settings.FlagSpots`) |
| `AutoBG_Options.lua` | Settings window, tabs General, Timers, Enemy frames, Spy |

Things to know:

- Enemy frames have separate sizes and positions per battleground size
  (10, 15, 40). In a match the settings page edits the size being played.
- Invites run out after about 80 seconds. The enter delay tops out at 78; an
  invite that ends before the scheduled enter is reported in chat.
- Requires ClassicAPI 1.17.7+ (guards check `11707`), SuperWoW and
  NamPower. UnitXP is no longer used.
- `AutoBG_SetPreview(on)` in Options is the one switch for every preview.
- Faction colors on timers and the Arathi Basin projection are always on; their
  old settings are cleared on load.
- A cast started from stealth never reaches the client (the caster is still
  invisible), so the flag watch warns when an enemy comes into sight at a
  flag and stands there. Visible openers show on their enemy frame cast bar.
