# AutoBG review — 2026-09-26

## Task and boundaries
- Type: addon-wide audit followed by bounded bug fixes and UI improvements.
- Baseline: main, 6c5cb6aeee92fd2ee03129501494aabf74651b74.
- Objective: improve BG readability, observed stealth alerts and PvP trinket tracking.
- Reviewed all six modules' responsibilities, event/timer ownership, settings and TOC order.
- Invariants: Interface 11200, existing DLL guards, optional UnitXP, English UI, saved custom positions.
- No DLL changes, new dependencies, addon version bump or new branch.
- Commit and push to the existing main branch authorized after the implementation review.
- Stop condition: tested working-tree patch and focused client test instructions.
- References: engineering contract, workflow, task/review/retrospective templates and relevant aura API reference. No framework knowledge promotion.

## Findings and implementation

| Area | Finding / action |
| --- | --- |
| Targets | Legacy mappings and fuzzy name paths used 300 seconds. One 180-second policy now covers supported exact IDs/names. Active cooldown observations cannot restart the timer. |
| Targets | Removed unsubstantiated 23505–23513 compatibility IDs and broad immunity/Insignia substring guesses. A custom spell can still match an exact known name via SpellInfo. |
| Stealth | BG frames had no audible alert; Spy exited during BGs. Targets now calls Spy's shared notification function on new observations, controlled by a separate BG setting. |
| Stealth | Shared aura-slot scan handles target, focus, mouseover and nameplate aura changes. Missing/invisible units return unknown, preserving the last observation. |
| Stealth | Unknown spell-ID / known-name duration lookup incorrectly selected zero. Named invisibility now retains its defined duration. Duplicate observations no longer extend the expiry. |
| Stealth | Unrelated casts and spell-damage messages could erase stealth. They no longer do; a fade must match the currently tracked effect, so a late Vanish fade cannot clear observed Stealth. |
| Spy | First detection within eight seconds of login could be silent. Stealth takes priority independently of the nearby-sound debounce. Shadowmeld gets its own row icon. UnitClass uses the class token return. |
| Lifecycle | Scoreboard refreshes repeatedly hid the popup. BG visibility changes now apply only on transitions. Spy identity/debounce caches clear on world entry/history reset; BG telemetry clears on exit. |
| UI | Larger names and rows, brighter slate panels and stealth labels, wider timers and carrier cards. One-time migration changes only dimensions matching the old defaults. The enemy container covers its rows for screen clamping. |
| FC | GetAuraSlots was mistaken for a returned table, skipping Assault stacks. Use the documented caller-owned output buffer and exact Focused/Brutal Assault names. Partial UnitXP health results cannot concatenate nil. |
| Queue | isAutoQueueing was declared after one consumer, creating separate global/local state. Shared locals now precede their consumers. Cancellation invalidates queue steps and deferred login/resurrection/finder callbacks. |
| Queue | Delayed acceptance now checks invitation generation, current map/status, acceptance state and current Auto-Accept preference. Completing request dispatch no longer claims server-confirmed registration. |
| Deserter | Removed icon-only identification that could confuse unrelated debuffs with Deserter. |
| Documentation | Removed unsupported zero-allocation, no-OnUpdate and performance guarantees from the README. |

## Evidence

[SOURCE-VERIFIED] The defects above were traced in AutoBG source. ClassicAPI's
[version-pinned API documentation](https://github.com/brues-code/ClassicAPI/blob/v1.15.14/docs/API.md#c_unitaurasgetauraslotsunit--filter--maxslots--continuationtoken)
defines GetAuraSlots as continuation token plus slot values, or continuation token
plus count when supplied an output table as argument five. GetAuraDataBySlot reads
the resulting slot IDs. Aura fields include name, spellId and applications.

The 180-second trinket duration is the user's deployment requirement, not an
independent measurement of server cooldowns. Retained trinket IDs and existing
custom stealth durations still need observed client/server confirmation.

UI inspiration: [BattleGroundEnemies player rows](https://github.com/BullseiWoWAddons/BattleGroundEnemies/blob/master/PlayerButton.lua)
separate name, health, target/focus and trinket information. This patch keeps those
roles distinct and improves text contrast in AutoBG's existing frames. No code or
assets were copied, and no modern WoW APIs were imported.

## Integration review and validation
- Correctness/ownership: regression coverage for duplicate events, old aura fades,
  queue cancellation, replaced invitations and popup visibility.
- API/dependencies: existing ClassicAPI 1.15.14 and SuperWoW floor retained;
  optional UnitXP retained; no new runtime file or dependency.
- Persistence: only Targets.ReadabilityVersion and Targets.StealthAlert are new
  persistent fields. Runtime generations, aura buffers and observations remain local.
- UI/load graph: six Lua files retain their TOC order; Targets precedes Spy,
  and options load last. Preview coverage covers 10/15/40 rows. Rendering is not
  validated by mocks.
- Automated command: python -B tests/test_runtime.py <directory-containing-lupa>.
  Uses lupa.lua51 with mocked WoW APIs; this is regression evidence, not client
  empirical verification.
- Validation: 16 Lua mock regressions and 40 framework regressions passed;
  addon linter reported zero errors/warnings; git diff --check passed.

## Client test checklist — [UNVERIFIED - TEST FIRST]
1. Reload Lua with errors enabled. Open /abg test and preview 10, 15 and 40 enemies.
   Check long names, contrast, timer labels, trinket numbers, saved positions,
   bottom-of-screen rows and target/focus clicks at your resolution/UI scale.
2. In a BG and outside one, observe a rogue Stealth/Vanish, druid Prowl and
   night-elf Shadowmeld. Expect the correct icon plus one sound/popup, including
   nameplate aura updates. Repeated events should stay quiet; a later new stealth
   after a confirmed break should alert again.
3. Leave/re-enter sight range and test Vanish > Stealth > Vanish-fade ordering.
   Unknown/unavailable enemies must not be falsely marked as having left stealth.
   Verify BG and open-world alert switches independently.
4. Observe each deployed PvP trinket variant. Expect 3:00 followed by a countdown,
   with no reset from duplicate gain/cast messages. Confirm actual cooldown and
   event spell IDs in the deployed client. Missing observations cannot reveal readiness.
5. Check WSG Focused/Brutal Assault stacks, carrier health and distance. Partial or
   unavailable UnitXP health must leave a usable percentage.
6. Queue multiple BGs then cancel before the next step. Test delayed acceptance
   while changing Auto-Accept or replacing an invitation. Check AFK, death,
   resurrection, Deserter, entering and leaving BGs.

## Remaining audit limitations / next priorities
- Custom AB/AV/WSG timing and AB projection constants need deployed runtime/data
  evidence. The AB prediction assumes 2000 resources and fixed resource rates;
  future capture/base ownership assumptions should be checked against real matches.
- English combat messages remain supplemental telemetry. Actual enemy aura/cast
  visibility and exact custom spell IDs have not been verified in a game session.
- The enemy roster and Spy use names for some joins; mixed-realm identity and
  unavailable enemies remain important runtime scenarios.
- No CPU/GC measurements or real-client visual screenshots were captured.

## Retrospective
The high-value findings came from tracing event consumers and delayed callbacks,
then running integrated Targets/Spy mocks. Checking the actual aura return
contract exposed a failure that syntax checking could not detect. A dedicated
late-fade test caught an unapplied edit before completion. Future work should
start with this harness and deployed event observations rather than repeating
framework discovery. These are addon-specific repairs; no new framework pattern
is proposed.

## Screenshot follow-up: dragging and timer presentation

The user screenshots exposed a bounds regression: enemy rows were below a newly
expanded container, leaving an invisible list-sized area above them. Rows now
start inside the container under a 20px preview-only drag header. Only that header
accepts movement input. Saved position data is retained; users may reposition the
corrected frame once.

Objective rows now have full-height progress fills, white outlined centered names,
right-aligned countdowns and a wider panel. Text/icons are parented to the status
bar so the fill cannot obscure them. The shared factory also updates WSG flag rows.
17 mocked Lua tests pass, including row containment and label/fill geometry.
Real-client drag/clamping and rendered legibility still need a reload test.
The user authorized committing and pushing this follow-up after the 17-test validation.

## Proximity-only stealth warnings

Scoped bug fix prompted by runtime feedback: remote stealth casts must update the
row indicators without producing popup/sound spam. Notification eligibility is now
separate from stealth state. Both BG and world paths require a directly observed
GUID, a live hostile player, client visibility, a current stealth aura, confirmed
distance <= 10 yards, and clear LOS. Missing evidence remains silent. The alert
latch is set only after a notification actually plays, allowing a later nearby
observation to qualify. Existing bounded timers retry pending observed enemies;
there is no new ticker. Pool/history resets clear the transient observation/latch.
The nameplate/target/mouseover/focus observation paths supply candidate identity;
cast/chat-only records do not. Row indicator behavior remains unchanged.

[SOURCE-VERIFIED] ClassicAPI v1.15.14 provides
[UnitDistanceSquared](https://github.com/brues-code/ClassicAPI/blob/v1.15.14/src/unit/Range.cpp)
with a checked-position return, and
[UnitInLineOfSight](https://github.com/brues-code/ClassicAPI/blob/v1.15.14/src/unit/LineOfSight.cpp)
with true/false/nil results using world collision. These do not require UnitXP.
Native UnitIsVisible alone is not treated as proximity or LOS evidence. Ten yards
is an addon alert policy, not a verified server stealth-detection formula or a
camera/front-arc calculation.

Validation: 21 Lua mock tests pass; linter has zero errors/warnings; diff check
passes. Regression cases include remote casts retaining icons, far/blocked/unknown
checks, later approach, identity mismatch, absent current aura and duplicate alerts.
No TOC, DLL requirement or SavedVariables changes. The patch is included with the subsequent compact timer maintenance update.

[UNVERIFIED - TEST FIRST] Reload and verify in a BG and the open world:
- Distant Stealth/Prowl/Meld casts: row indicator, no popup or stealth sound.
- Directly observed stealthed opponent within 10 yards and unobstructed: one alert.
- Opponent behind a wall or out of range: silence; approaching/clearing LOS may
  alert if the unit remains observed. Repeated updates must not replay the alert.
- Row icons and labels must remain as before, regardless of notification eligibility.

Retrospective: a state-change notification was too broad for the requested threat
warning. Keep the independently tested presentation state and notification gate;
do not promote this addon-specific radius into framework policy.


## Compact AB/AV timer redesign
User feedback supersedes the earlier tall objective-row design. AB/AV now use 260-pixel groups, 24-pixel rows, flat full-height fills, muted faction colors, unoutlined Arial Narrow labels with a light shadow, and a transparent 19-pixel heading. Objective names remain centered; countdowns stay right-aligned and become amber at ten seconds. The shared factory stores each group's geometry so dynamic height follows the chosen style. WSG retains its existing row dimensions.

Validation: 21 mocked regression tests pass, including both objective layouts; Lua compilation and the linter pass. No manifest, dependency or SavedVariables changes. In-game visual verification remains pending: use Test All Frames, inspect long AV names and full/empty bars against bright terrain, drag the heading, and Ctrl-click a timer. The pending proximity-only stealth fix is included in this maintenance push.

Retrospective: reduce row height and decorative chrome without shrinking objective names; no framework knowledge promotion is needed.


## Permanent enemy-frame features and compact FC panels
User-requested simplification: remove independent-position, health-bar, flag-icon and stealth icon/text toggles. Runtime display no longer consults the retired booleans. Bracket enable labels identify 10v10/15v15/40v40. A one-time migration copies shared coordinates into separate tables while preserving actively independent positions; reset affects only its selected bracket and does not reseed it. No TOC or DLL dependency changes.

Flag-carrier panels were enlarged in 4b4ef44, not the subsequent timer update. They now use 220x42 dimensions, 24px icons and 12px health bars. Runtime verification remains pending: reload with existing settings, switch/drag/reset each bracket independently, inspect carrier name/distance/health, and confirm stealth and flag icons still appear when applicable.

Retrospective: permanent presentation choices should not retain user-facing toggles; migrating shared coordinates requires independent copies and a one-time marker.

## Deep architectural review: Stealth alerts, cross-realm resilience & visual legibility

A deep architectural review of AutoBG uncovered several latent bugs and integration flaws:

1. **Stealth alert & sound restoration**:
   - The prior proximity-only stealth check introduced in d94c708 blocked stealth notifications from functioning in real gameplay. `Targets` passed `observedGUID` as `observedUnit`, which failed native unit checks (`UnitGUID`, `UnitDistanceSquared`, `UnitExists`).
   - In addition, hostile players who enter stealth 15-30 yards away (via `UNIT_CASTEVENT` or combat log) have no active unit token, and become invisible (`UnitIsVisible` is false). In WoW 1.12, combat log / cast event packets are already restricted by the server to the entity awareness bubble (~30-40 yards).
   - `NotifyStealth` is restored to immediately trigger `PlayStealthDetectedSound()` and `Spy:ShowAlert` with a 5-second per-player debounce. When an enemy drops stealth (or dies/attacks), the debounce latch is reset so subsequent re-stealths (e.g. Vanish) alert reliably.

2. **Cross-realm entity resolution & selection**:
   - In cross-realm battlegrounds, roster names have realm suffixes (`"Player-Realm"`), whereas native target/focus queries return `"Player"`.
   - `UpdateRowSelectionVisual`: Now checks exact GUID match first (`targetGUID == btn.targetGUID` / `focusGUID == btn.targetGUID`), falling back to `StripRealm(btn.targetName)`. Target (gold) and focus (cyan) borders now highlight correctly in cross-realm BGs.
   - `TargetButton_OnClick`: Left-click falls back to `TargetByName(StripRealm(name), true)` when GUID is not yet cached. Right-click focus falls back to targeting by stripped name before applying `FocusUnit("target")`.
   - `AutoBG_FC`: `ScanCarrier` strips realm suffix before matching `UnitName(u)`, enabling flag carrier health, assault stacks, and GUID tracking in cross-realm WSG. Left-click target and right-click focus also strip realm suffix.
   - `AutoBG_Spy`: Fixed `guidToName` lookup in row clicking and added `nameToGUID` cache. Click-to-target and alert-window clicking strip realm suffixes.

3. **Objective timer legibility**:
   - Arial Narrow text in compact AB/AV node bars now uses `"OUTLINE"` font flags, providing crisp separation against bright terrain textures (snow in AV, grass in AB).

Validation:
- 23 unit tests pass (`python -m unittest discover -s tests -p "test_*.py" -v`).
- 40 VanillaForge framework tests pass.
- VanillaForge linter: 0 errors, 0 warnings.


## Follow-up correction: blank objective text and live dragging
This correction supersedes the intervening Gemini stealth-notification and Arial-outline recommendations above. A debounce alone does not meet the user's proximity-only warning requirement. The original live-aura, identity, 10-yard and LOS checks and their regression tests are restored; cross-realm targeting changes are retained. Claims above that GUID checks fail are not established by this audit.

The screenshot shows missing objective text and fill. The compact design introduced different font/texture paths; this patch uses the established Friz font, inherited GameFontHighlightSmall and bundled bar texture. Missing client assets are a suspected cause, not an empirically proven diagnosis. Runtime verification is required.

Enemy drag headers are always shown with the live list and no longer require configuration mode. Objective row buttons forward drag start/stop to their group and save position. AB forecast dragging no longer requires Shift. Queue, respawn and FC drag handlers remain available.

25 mocked regressions pass, including live-header and timer-row dragging, remote-stealth silence and retained cross-realm tests. Linter reports zero errors/warnings. After reload: check Blacksmith name/countdown/fill, drag each visible widget, verify saved bracket positions, and confirm ordinary target clicks and Ctrl-click announcements still work. No manifest/dependency changes; no new frame ticker. User authorized committing and pushing this maintenance update.
