# AutoBG

Battleground helper: queueing and auto-enter, objective timers, flag carriers,
enemy frames and the Spy enemy list. Player guide: `docs/USER_GUIDE.md`.
Regression tests: `regressions/AutoBG` in VanillaForge (235 tests).

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
  invite that ends before the scheduled enter is reported in chat. Leaving
  the queue (AcceptBattlefieldPort without accept, hooked) is not.
- Queues go through `JoinBattlegroundQueue(type)`, defined by OctoWoW's own
  FrameXML (Minimap.lua); `BATTLEGROUNDS` in AutoBG.lua holds each type and
  queue-bar icon. The server answers with BATTLEFIELDS_SHOW, where AutoBG joins
  the Cross-Faction row when listed (client 2026.10.31: reserved instance
  OCTO_BG_ROW_XF_ID 9001 after First Available; the player's choice, always
  Cross-Faction), else First Available. Queue bars use OctoBGQueueName.
- Arenas (client FrameXML Turtle_ArenaUI.lua): `JoinArenaQueue(0)` Skirmish,
  1-3 Rated 2v2/3v3/5v5; `LeaveArenaQueue()`; the queue status map is ARENA.
  One arena queue at a time, three queues in all. `AutoQueue_Arena` and
  `ArenaType` queue one with the battlegrounds. In an arena: no auto-release,
  no spirit-healer bar, their own enemy frames (bracket key 5, own size, position and options;
  the roster is the scoreboard plus enemies seen; Targets detects an arena by
  the zone too, not only the queue status) next to Spy, which also works
  there; rejoin queues the arena again. `AutoBG_IsArenaZone` (AutoBG.lua) is
  the one place that names the arena zones: Lordaeron Arena, Sunstrider Court,
  Blood Ring (confirmed by the player 2026-11-03). UNVERIFIED: the arena's instance type
  and whether Skirmish answers with BATTLEFIELDS_SHOW. It does (2026-11-04): the
  window is titled with the arena zone ("Blood Ring") and lists First Available, so
  `ShownBattlefield` (AutoBG.lua) maps those titles to ARENA.
- Cross-faction (2026-11-04): teams mix Alliance and Horde in Warsong, Arathi Basin
  and the arenas (not Alterac Valley), so the enemy list is corrected by what you
  can attack, not by faction. An arena lists the other team from the server's own
  arena scoreboard (CHAT_MSG_ADDON prefix TW_ARENA, "S2C_SCOREBOARD;<winner>;<count>;
  name|team|x:...", read in client WorldStateFrame.lua; registered only in an arena)
  plus attackable players seen. A battleground starts from the scoreboard, drops a
  roster name that is not attackable (`VerifyEnemy`) and adds a hostile player it
  lacks (`LearnOpponent`). UNVERIFIED: whether the scoreboard's faction column is
  the team or the real faction on a mixed team.
- An arena is told by `AutoBG_IsArenaZone` only (IsActiveBattlefieldArena, the zone
  names), never by the queue status: the status can still say "active" after you
  left, which made AutoBG think it was in the arena and stalled auto-rejoin.
- Requires ClassicAPI, SuperWoW and NamPower: AutoBG.lua's guard checks all
  three and says what is missing; the other files check ClassicAPI and
  SuperWoW. UnitXP is not used.
- `AutoBG_SetPreview(on)` in Options is the one switch for every preview
  (`/abg test`, `/abg t`, the button, closing the window). Options owns the
  timer and carrier preview flag and passes it on (`AutoBG_Timers_SetPreview`,
  `AutoBG_FC_SetPreview`); it is never saved.
- OctoWoW battlegrounds are cross-realm: players can be named "Name-Realm"
  (Spy stats hold "Mayve-NZ" from Alterac Valley). The realm handling and
  "Hide realm names" are live; one helper, `Targets.StripRealm`.
- Faction colors on timers and the Arathi Basin projection are always on; their
  old settings are cleared on load.
- Every timer (objectives, game start, respawn, queues) is a row from one
  factory in `AutoBG_Timers.lua`. Objectives use our own icons
  (`Textures\Nodes\<Kind>_<Alliance|Horde|Neutral>.tga`, 64x64 TGA): one per
  AB base, a keep for AV bunkers and towers, a headstone for graveyards, a
  pick for mines. WSG flags keep the banners (`INV_BannerPVP_01` Horde, `_02`
  Alliance). `Textures\Gloss.tga` bar, cast-bar spark, BigWigs clock
  ("21", "1:51"). Rows with an expiry drain by themselves (`SetTimerDuration`, ClassicAPI
  1.19; the spark rides the bar texture); `OnUpdate` only rewrites the clock when
  the second changes. Preview and queue rows hold a value. The logic ticker runs
  once a second. The frame preview is never saved.
- The flag watch runs in Arathi Basin only; in Alterac Valley it was noise
  (player's call, 2026-10-27), and saved spots for other maps are dropped on
  load. It warns on a visible enemy's Opening cast start (NamPower SPELL_START_OTHER, no
  enemy frames needed). A cast started from stealth never reaches the client,
  so it also warns when an enemy comes into sight at a flag and stands there.
  Spots are learned only from named assault and defend messages; "taken"
  messages teach nothing.
- The game start timer reads only lines about the battle beginning ("1 minute
  until the battle for Alterac Valley begins."). "This game will close in 30
  seconds" (too few players) once started it by mistake.
- Events are registered only where they are used. Enemy frames: match events
  only in a battleground or the preview (`SyncMatchEvents`). Match-end chat
  (AutoBG.lua) and objective lines (Timers) only inside a battleground. Spy:
  sightings only while its list works (`SyncTelemetry` in `MaintainTicker`);
  it rests in any battleground instance, whatever the queue status says.
  Carrier health: NamPower UNIT_HEALTH_GUID while a carrier is tracked; a
  0.5 s ticker finds the unit and reads the distance.
- Casts come from SuperWoW UNIT_CASTEVENT alone (enemy frames and Spy). It
  reports every unit's casts, instants included, and the swings that end
  stealth; ClassicAPI UNIT_SPELLCAST_SUCCEEDED gave the same casts for fewer
  units. Enemy cast bars are status bars on a reused duration
  (`SetTimerDuration`): no OnUpdate. Another unit's pushback is never sent to
  the client (ClassicAPI docs), so nothing re-reads a running cast; the 0.5 s
  ticker ends casts the engine cleared without an event and loops the samples. Unit events
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
