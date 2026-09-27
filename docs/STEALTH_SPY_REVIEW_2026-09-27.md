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
