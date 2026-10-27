# AutoBG

Battleground helper: queueing and auto-enter, objective timers, flag carriers,
enemy frames and the Spy enemy list. Player guide: `docs/USER_GUIDE.md`.
Regression tests: `regressions/AutoBG` in VanillaForge (195 tests).

| File | Job |
| --- | --- |
| `ForgeUI.lua` | The shared settings kit (ForgeUI) |
| `AutoBG.lua` | Settings and defaults, queue pops and auto-enter, match end, auto-rejoin, `/abg` commands |
| `AutoBG_Timers.lua` | Base and node countdowns, game start, spirit healer waves, queue times, Arathi Basin projection |
| `AutoBG_FC.lua` | Warsong Gulch flag carrier frames |
| `AutoBG_Targets.lua` | Enemy frames: health, cast bars, range fading, raid icons, trinkets, stealth |
| `AutoBG_AlertCard.lua` | The popup card kit (`ns.CreateAlertCard`); the stealth and flag warnings each own one |
| `AutoBG_Spy.lua` | Enemy list and stealth alerts outside battlegrounds; off in raids by default |
| `AutoBG_FlagAlert.lua` | The flag warning card, Ctrl+click announce; learns the Opening spell (`AutoBG_Settings.OpeningSpell`) |
| `AutoBG_FlagWatch.lua` | Arathi Basin only: enemy Opening casts and enemies out of stealth at a flag; learns flag spots per map (`AutoBG_Settings.FlagSpots`) |
| `AutoBG_Options.lua` | Settings window, tabs General, Timers, Enemy frames, Spy |

Things to know:

- Enemy frames have separate sizes and positions per battleground size
  (10, 15, 40). In a match the settings page edits the size being played.
- Invites run out after about 80 seconds. The enter delay tops out at 78; an
  invite that ends before the scheduled enter is reported in chat.
- Requires ClassicAPI 1.17.11+ (guards check `11711`), SuperWoW and
  NamPower. UnitXP is no longer used.
- `AutoBG_SetPreview(on)` in Options is the one switch for every preview.
- Faction colors on timers and the Arathi Basin projection are always on; their
  old settings are cleared on load.
- Every timer (objectives, game start, respawn, queues) is a row from one
  factory in `AutoBG_Timers.lua`. Objectives use our own icons
  (`Textures\Nodes\<Kind>_<Alliance|Horde|Neutral>.tga`, 64x64 TGA): one per
  AB base, a keep for AV bunkers and towers, a headstone for graveyards, a
  pick for mines. WSG flags keep the banners (`INV_BannerPVP_01` Horde, `_02`
  Alliance). `Textures\Gloss.tga` bar, cast-bar spark, BigWigs clock
  ("21", "1:51"). Rows drain and change their text in `OnUpdate`; the logic
  ticker runs once a second. The frame preview is never saved.
- The flag watch runs in Arathi Basin only; in Alterac Valley it was noise
  (player's call, 2026-10-27), and saved spots for other maps are dropped on
  load. It warns on a visible enemy's Opening cast start (UNIT_CASTEVENT, no
  enemy frames needed). A cast started from stealth never reaches the client,
  so it also warns when an enemy comes into sight at a flag and stands there.
  Spots are learned only from named assault and defend messages; "taken"
  messages teach nothing.
- The game start timer reads only lines about the battle beginning ("1 minute
  until the battle for Alterac Valley begins."). "This game will close in 30
  seconds" (too few players) once started it by mistake.
- Events are registered only where they are used. Enemy frames: match events
  only in a battleground or the preview (`SyncMatchEvents`). Spy: sightings
  only while its list works (`SyncTelemetry` in `MaintainTicker`). Unit events
  use `RegisterUnitEvent` for the tokens that matter (target, focus,
  mouseover, nameplates; `player` for Deserter; raid tokens for revivals, in
  battlegrounds only). In a battleground the stealth alert comes from the
  enemy frames' roster, with the frames for that size on or off, and Spy shows
  it with its list off. Aura listeners take `UNIT_AURA_DELTA` (1.17.10) and
  skip refresh-only changes (only updated IDs), which never change stealth
  or Deserter.
- Enemy rows, their cast bars and the carrier cards are ClassicAPI unit
  buttons (`Targets.BindUnit`) once the GUID is known: type1 target, type2
  focus, hover is the mouseover. Ctrl and Shift clicks carry the unknown verb
  "own" so they reach the frame's OnClick (Ctrl-click announce). Anything
  unbound (Spy rows, warning cards, `/abg efc`, a row before its GUID) goes
  through `Targets.SelectEnemy`: an exact-name `UnitTokenFromName` lookup and
  one off-screen unit button. No TargetUnit, FocusUnit, TargetByName or
  SetMouseoverUnit is left.
- Names resolve through ClassicAPI, not roster walks: `UnitTokenFromName` (flag
  watch, base message faction) and `C_PlayerCache.GetPlayerInfoByName`
  (carrier class; the scoreboard only for enemies never seen).
