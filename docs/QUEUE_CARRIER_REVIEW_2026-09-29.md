# Queue and carrier integration review — 2026-09-29

Classification: audit, bounded implementation, integration review. Starting
commit: `048b0f7879fbabb8ee662342acb888e089af0c64`; main and working tree were
clean, and the actual remote main matched. Reused the September 26 module audit
and September 27–28 Spy audit, including the latest accepted warning policy.

## Architecture and API consumption

The six TOC entries load core/settings, timers, flag carriers, enemy roster,
Spy, then options. `AutoBG_Settings` is the only persisted root. Queue generation,
pending invitation ownership, carrier names/GUIDs and roster observations are
session state. Core handles login, battlefield status, death, zone and queue
events. Objective/resurrection/queue rendering uses a 0.1-second ticker; carrier
scanning uses 0.15 seconds; temporary stealth expiry has its existing throttled
OnUpdate. No ticker or render cadence changed.

Core owns queue commands and settings/positions; Timers owns objective groups;
FC owns two 220-by-42 cards and the exported carrier API; Targets owns bracket
rosters and shared stealth state; Spy owns the open-world roster and shared alert
window; Options owns controls. Reset, scale and drag behavior remain covered by
the existing suite. There are no item/equipment transactions in this addon.

ClassicAPI provides `C_Timer`, structured `C_UnitAuras` slots/data, exact unit
lookup, focus, range and LOS. SuperWoW supplies GUID-aware targeting, mouseover
and cast events; optional UnitXP supplies supplementary carrier health/distance.
NamPower is not consumed. DXVK is not an addon dependency. Existing ClassicAPI
1.15.15 / SuperWoW 2.2 requirements and optional UnitXP status are unchanged.

Authoritative API recheck: ClassicAPI v1.15.15 at
`71805db62f1e8a154477033dc1f50960c535af8b`:
[API contract](https://github.com/brues-code/ClassicAPI/blob/71805db62f1e8a154477033dc1f50960c535af8b/docs/API.md),
[focus implementation](https://github.com/brues-code/ClassicAPI/blob/71805db62f1e8a154477033dc1f50960c535af8b/src/unit/Focus.cpp),
[position implementation](https://github.com/brues-code/ClassicAPI/blob/71805db62f1e8a154477033dc1f50960c535af8b/src/unit/Position.cpp).
`UnitDistanceSquared` returns both a number and a validity flag; `(0, false)` is
unknown, while `(0, true)` is valid. `FocusUnit` has no success return, and a
successful Lua call is not proof of the intended identity. Existing structured
aura, event and GUID paths remain; no speculative replacement API was added.

## Findings and bounded fixes

Locations below refer to the starting commit.

| Priority / evidence | Location | Reproduction and consequence | Implemented correction |
| --- | --- | --- | --- |
| P2 [SOURCE-VERIFIED] | `AutoBG.lua:711` | Load an old/manual string, table, negative or excessive `AutoAcceptDelay`; queue comparisons/UI may receive invalid values. | Normalize once at load to an integer from 0 through 120, preserving numeric strings. |
| P2 [SOURCE-VERIFIED] | `AutoBG.lua:807` | Disable login autoqueue during its three-second delay; the old callback still queues. | Recheck the current setting in addition to generation ownership. |
| P2 [SOURCE-VERIFIED] | `AutoBG_FC.lua:76`, `:465`, `:495` | Cached carrier GUID disappears or resolves incorrectly; a silent call is treated as success. Failed exact-name lookup followed by focus selects the previous target. | One shared selector validates live player identity, resolves the current token, checks exact-name fallback and verifies target/focus before reporting success. Two fully qualified names must match realms. |
| P2 [SOURCE-VERIFIED] | `AutoBG_FC.lua:283` | An unavailable position returns `(0, false)`; the card shows a fabricated zero-yard distance. | Honor the validity result; retain the existing supplementary providers and question-mark display. |
| P2 [SOURCE-VERIFIED] | `AutoBG_FC.lua:438`, `:443`, `:454`, `:485` | As Horde, only the opposite requested carrier exists. Lua's `and/or` expression substitutes that other carrier when the desired one is nil. | Explicit faction branches preserve nil, and commands use the same public selectors. |

The defects are reproduced in Lua 5.1 mocks. That establishes addon control flow,
not live-client behavior. No new P0/P1 finding was established in this pass.

## Validation and integration review

- 56 Lua 5.1 tests pass: 45 inherited tests and 11 new queue/carrier tests.
  Nine new defect regressions fail at behavior assertions against the starting
  commit; two positive controls exercise ordinary login queue and exact targeting.
- All six tracked Lua files compile and all six TOC entries resolve. No orphan
  Lua file, load-order or dependency change.
- VanillaForge strict lint on a copy of tracked files: zero errors/advisories.
  Ignored local `Claude_Reply` content is excluded from review and publication.
- Complete staged diff and `git diff --check` reviewed. Only the delay field
  is normalized; no setting is added, no transaction state is persisted.
- Existing options creation, bracket resets/scale, timer layout and display,
  aura/event sequences, both Spy modes and BG proximity policy remain covered.
  Native game rendering is outside the mock suite and remains a runtime check.

## In-game acceptance — pending

1. With WoW closed, back up SavedVariables; set the delay to a nonnumeric string.
   Log in, open `/abg`, confirm delay zero and normal controls. Restore a numeric
   delay, accept an invitation, and verify cancel/replacement invites cannot
   execute an old callback. Test AFK and Deserter guards.
2. Enable login queue, reload, immediately disable it before three seconds;
   no request should follow. Leave enabled for the positive case.
3. In WSG, exercise left/right clicks and target/focus commands with a visible
   carrier, a carrier leaving visibility, and an unrelated current target.
   Missing carriers must not change focus or print successful selection.
4. On Horde, test each flag held separately: missing friendly/enemy queries and
   commands must remain empty. Repeat both flags held and flag return/capture.
5. Verify distance at known zero/near/far range and after the carrier unloads;
   unknown is `? yd`. Recheck health/debuff redraw after target/aura changes.
6. Open Test All Frames; drag, scale and reset each bracket and carrier card;
   close/reopen options and reload. Check native statusbar redraw and alignment.
7. Repeat the existing Spy acceptance matrix: nearby-only on/off, distant cast,
   visible hostile aura within ten yards and clear LOS, wall, fade/re-entry,
   repeated episode, and BG proximity-only warnings. Policy is unchanged.

[UNVERIFIED - TEST FIRST] Localized/server chat variants may omit carrier or
objective transitions; no server-specific parsing behavior was guessed here.
If reproduced, record event text, zone, client locale and loaded DLL versions.

## Retrospective

Optional values must remain optional through faction selection, distance reads
and delayed callbacks. A nonthrowing target/focus call does not establish identity.
These are already represented by framework identity/state principles; no
VanillaForge change or new global policy is proposed.
