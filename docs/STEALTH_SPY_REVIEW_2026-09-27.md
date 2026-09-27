# Stealth and compact Spy regression review — 2026-09-27

## Scoped bug fix

- Objective: retain Stealth/Vanish indicators, improve explicit target clicks,
  and remove the oversized empty Spy strip. No timer/FC redesign.
- Baseline: 885f748c381bb82541c1fd9a0e8c9083302825e8.
- Routing: VanillaForge AGENTS.md, contract, ClassicAPI API reference, engine
  cast-event reference, workflow and task/review/retrospective templates.
- Preserve: Stealth/Invis/Prowl/Meld row metadata independent of distance;
  popup/sound restricted to directly observed nearby units; 180s trinket policy,
  independent bracket positions, live dragging and timer appearance settings.
- Initial implementation stayed local. The maintainer subsequently authorized
  committing and pushing all scoped changes to main on 2026-09-27. Runtime
  verification remains pending after publication.

## Findings and changes

| Finding | Correction |
|---|---|
| Only SuperWoW CAST was handled; ClassicAPI instant successes were ignored | Add UNIT_SPELLCAST_SUCCEEDED to BG and world handlers. Keep raw-GUID events for sources without a standard token; repeated events share existing state/debounce. |
| Immediate empty aura data erased a new cast; a missing slot was treated as absence | Protect event-derived state for 0.5s; one recheck on existing tickers. Missing/unavailable snapshots remain unknown. Explicit fades, swings and visible death still clear immediately. |
| A previous dead flag suppressed a new successful stealth cast | New successful casts/gains supersede it; invisible health/death snapshots retain last observed state. |
| Spy assumed frame/event arguments only | Normalize frame/event, event-first and original global event arguments without shifting nil payload fields. |
| Cached GUID was always attempted even when departed or belonging to another name | Share validated selection across BG rows, Spy rows and alerts. Use the loaded matching GUID; otherwise use exact-name targeting. Known full realm names are compared when available. |
| Empty Spy used the same 260px width as populated rows | Empty header becomes 96x24; populated rows retain readable dimensions. Saved Scale and AutoHide preferences are untouched. |

[SOURCE-VERIFIED] Version-pinned
[ClassicAPI documentation](https://github.com/brues-code/ClassicAPI/blob/71805db62f1e8a154477033dc1f50960c535af8b/docs/API.md)
and [CastEvents.cpp](https://github.com/brues-code/ClassicAPI/blob/71805db62f1e8a154477033dc1f50960c535af8b/src/spell/CastEvents.cpp)
confirm remote UNIT_SPELLCAST_SUCCEEDED, including instants, and per-token fan-out.
It does not fan out SuperWoW raw GUID tokens. Existing SuperWoW events remain
useful for those GUID observations. Aura slots and missing snapshots follow the
same release's documented C_UnitAuras contract. The settling duration is an addon
policy, not an upstream guarantee about server latency.

The user's exact lost rogue observation cannot be reconstructed from screenshots:
no runtime event trace was supplied. The prior source demonstrably fails the
reported classes of state/selection cases in mocks. These corrections are not a
claim that an addon can reveal or target an undetected stealthed opponent.

## Validation and integration review

- 36 Lua 5.1 regressions pass (26 retained, 10 added), covering modern/legacy
  events, Vanish-to-Stealth ordering, early/missing auras, stale death/health,
  explicit fade/swing cleanup, duplicate warning suppression, retained proximity
  checks, target identity, and compact empty header/scale/autohide transitions.
- Seven selected new regressions were run against committed source: all fail;
  the corrected source passes all seven. Mock results are not game empirical
  verification. No new ticker or broad roster polling was introduced.
- Lua compilation and strict linter pass: 0 errors, 0 advisories.
  git diff --check passes. Full changes and new artifacts reviewed.
- TOC and dependency guards unchanged (published ClassicAPI v1.15.15+ floor).
  pendingUntil is pooled/transient runtime state, never SavedVariables.
  Saved Spy/bracket positions and preferences are preserved.
- Review: correctness, event ownership, API provenance, persistence, docs and
  scoped changes pass static review. In-game delivery/rendering is still pending.

## Runtime checklist — [UNVERIFIED - TEST FIRST]

1. `/reload`; in a BG observe rogue Stealth and Vanish, druid Prowl, Meld and
   invisibility. Verify labels after resurrection, loss of visibility and target
   changes. Explicit fade, attack or observed death must clear the matching state.
2. Distant casts must update row labels without warning spam. A directly observed
   stealthed hostile within 10 yards and clear LOS should alert once. Unknown
   range/LOS must stay silent. Native targeting still requires a selectable unit.
3. Click BG and Spy rows for detectable players, including one who left and
   returned to range. Verify left target/right focus and cross-realm names.
4. Outside a BG test empty/populated/empty Spy, custom scale, AutoHide and drag
   persistence. Populated names and stealth tags must remain readable.
5. If the rogue case persists, record UNIT_CASTEVENT, UNIT_SPELLCAST_SUCCEEDED,
   UNIT_AURA and UNIT_HEALTH with timestamps and unit/GUID identity in an event
   trace. Avoid changing alert gates based only on a missing indicator.

## Retrospective

Separating row state from warning policy preserved the requested quiet popup
behavior. State tests against the committed revision established concrete
regressions without guessing the exact unseen match sequence. A late state review
found stale death flags were another suppressor; a resurrection/Vanish test now
covers it. Framework evidence/ownership rules already cover the general lessons;
no VanillaForge or other addon changes are required.

## Spy class-icon follow-up — 2026-09-27

Scoped bug fix from f1c7cf0. The maintainer reported stealth-looking icons on
ordinary classes; the screenshot's affected rows still show health percentages
rather than stealth state labels. That suggests an icon-rendering defect; it
does not establish an actual false stealth event in the running game.

[SOURCE-VERIFIED] The normal icon branch used an undefined external
CLASS_ICON_TCOORDS global with Interface/WorldStateFrame/Icons-Classes. Without
that table, every class received the same broad crop. AutoBG does not define
that table. Its source-level rendering defect is reproducible independently of
stealth classification. The replacement uses a local nine-class mapping for
the character-create class atlas, with insets matching the existing local
LunaUnitFrames-TurtleWoW class-portrait implementation (LunaUnitFrames.lua
constants and modules/portrait.lua). No Luna dependency or new asset is added.

Normal rows restore their class texture and crop on every render, including
after reusing a stealth row. Unknown classes hide the icon. No change to aura/
cast classification, popup/sound distance/LOS gates or BG row state. A class
restriction would be incorrect for effects such as racial Meld and items.
Settings, positions, TOC and DLL requirements are unchanged.

Validation: both new class-rendering regressions fail against the old source;
all 38 Lua 5.1 regressions pass with the fix. Tests now record SetTexCoord
instead of silently accepting it. Cover all nine distinct crops without an
external global, isolation from a conflicting global, recycled rows, unknown
class icons and warrior Meld-to-normal transitions. Existing stealth/proximity
and BG regressions remain intact. Strict linter: 0 errors, 0 advisories.

[UNVERIFIED - TEST FIRST] Sync and reload. Normal Spy entries should show distinct
class icons and health text. A real Stealth/Prowl/Vanish/Meld/Invisibility
observation should show its effect icon/label, then restore the class icon on
an observed fade. Verify the atlas appearance in the actual game folder. If a
normal enemy still shows a STEALTH label or triggers a stealth warning, retain
the name/class/effect and event trace: that is a separate state observation.

Retrospective: earlier mocks validated texture paths and state but ignored
texture coordinates, leaving the class atlas branch uncovered. Record those
coordinates for visual-state transitions. The general faithful-UI-mock lesson
is already covered by the framework; no VanillaForge change is needed.
