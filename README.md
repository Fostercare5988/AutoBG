# AutoBG

The [2026-09-29 queue/carrier review](docs/QUEUE_CARRIER_REVIEW_2026-09-29.md)
fixes stale login queue callbacks, malformed saved accept delays, carrier
target/focus identity, missing Horde carrier selection and unknown distances.
56 Lua 5.1 regression tests pass. In-game acceptance remains pending; Spy warning
policy, battleground layout and dependency requirements are unchanged.

**Required:** [ClassicAPI v1.15.15+](https://github.com/brues-code/ClassicAPI) and [SuperWoW v2.2+](https://github.com/balakethelock/SuperWoW). **Optional:** [UnitXP SP3](https://codeberg.org/konaka/UnitXP_SP3). Spy stealth warnings use ClassicAPI for distance and line of sight; UnitXP is not required. Fully restart WoW after changing a DLL (`/reload` cannot reload it).

[![Interface: 1.12.1](https://img.shields.io/badge/Interface-1.12.1%20(5875)-orange.svg)](https://github.com/Fostercare5988/AutoBG)
[![Version: 2.0.0](https://img.shields.io/badge/Version-2.0.0-blue.svg)](https://github.com/Fostercare5988/AutoBG/releases)
[![ClassicAPI: v1.15.15+](https://img.shields.io/badge/ClassicAPI-v1.15.15+-green.svg)](https://github.com/brues-code/ClassicAPI)
[![SuperWoW: v2.2+](https://img.shields.io/badge/SuperWoW-v2.2+-brightgreen.svg)](https://github.com/balakethelock/SuperWoW)
[![UnitXP: optional](https://img.shields.io/badge/UnitXP-SP3%20optional-teal.svg)](https://codeberg.org/konaka/UnitXP_SP3)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**AutoBG v2.0.0** provides PvP automation and battleground information for **World of Warcraft 1.12.1 (Build 5875)**. It requires **ClassicAPI v1.15.15+** and **SuperWoW v2.2+**. **UnitXP SP3 is optional** for additional carrier-distance and raw-health data when available.


Created and actively maintained by **[Fostercare5988](https://github.com/Fostercare5988)**.

---

## 🚀 Engine Architecture & Performance

AutoBG is engineered around strict low-level system integration:

| Engine Component | Minimum Version | Architectural Role & Implementation |
| :--- | :--- | :--- |
| **ClassicAPI** | `v1.15.15+` (required) | Timers, structured aura queries, exact-name unit lookup, distance and line-of-sight checks used by Spy alerts. |
| **SuperWoW** | `v2.2+` (required) | GUID targeting, exact-name targeting, mouseover support and raw-GUID cast events. |
| **UnitXP** | `SP3` (optional) | Additional carrier-distance and raw-health reads when available. Spy distance and line-of-sight checks do not depend on it. |

### Update and rendering model
- Objective and flag-carrier updates use ClassicAPI tickers; temporary stealth expiry uses a throttled OnUpdate watcher.
- Roster and aura-slot scratch tables are reused. No measured allocation or frame-rate guarantee is claimed.
- UnitXP supplies distance measurements when available; unknown distances display a question mark.
- Health-bar children disable mouse interception so clicks reach the carrier card.

---

## ⚡ Key Features

### 1. Automation & Queue Engine
- **Instant Match Exit**: Calls LeaveBattlefield(0) when match completion is detected and Auto-Leave is enabled.
- **Auto-Rejoin**: Requests the same battleground queue after leaving a completed match, once the previous active queue slot clears. Queue acceptance still depends on the server.
- **1-Click Multi-Queue**: Sends sequential requests for selected battlegrounds. Server queue status confirms registration; cancelling invalidates pending steps.
- **Auto-Accept with Configurable Delay & AFK Guard**: Instant entry (0s) or configurable countdown slider (0–70s, up to 120s via command). Automatically pauses auto-enter and auto-queue operations whenever you are tagged as AFK to prevent deserted debuffs.
- **Smart Spirit Release**: Auto-releases spirit upon death inside battlegrounds while safely preserving active Soulstones and Reincarnation (Ankh).
- **Taskbar Window Flashing**: Calls `FlashClientIcon` for queue notifications when the loaded client provides that function.

### 2. Objective & Base Timers
- **Arathi Basin (AB)**: 60s node capture countdowns with faction color-coding (Red = Horde, Blue = Alliance).
- **Alterac Valley (AV)**: 300s bunker, tower, and graveyard capture countdowns.
- **Warsong Gulch (WSG)**: 23s flag respawn countdowns (zone-isolated).
- **Match Gates**: Universal pre-match gate countdowns (120s, 60s, 30s, 15s).

### 3. Server-Synchronized Spirit Healer Engine
- Live 30-second Spirit Healer resurrection wave synchronization aligned with `GetAreaSpiritHealerTime()`, `PLAYER_UNGHOST`, and `PLAYER_ALIVE`.
- Dynamic 4-stage color-graded status bar:
  - **> 10s**: Bright Green
  - **5 – 10s**: Yellow
  - **2 – 5s**: Orange
  - **<= 2s**: Alert Red

### 4. Warsong Flag Carrier (FC) HUD & Domain Authority
- **Sole Architectural Authority**: Serves as the authoritative provider of Warsong Gulch Flag Carrier state, 3D Euclidean distances, and aura stacks across the entire addon suite (eliminating redundant polling engines in FosterFrames and BattlegroundTargets).
- **Public Query API**: Exports `AutoBG_GetCarrier(faction)` and `AutoBG_GetCarrierInfo(faction)` for query access by external frames and macros.
- Clickable unit cards for Alliance and Horde flag carriers with **SuperWoW Hybrid Targeting** (`TargetUnit(guid)` with `TargetByName(name, true)` fallback).
- Native SuperWoW mouseover support (`SetMouseoverUnit`) allowing mouseover macros directly over FC cards.
- Real-time uncapped carrier HP and percentage via **UnitXP SP3** with class-color resolution.
- Live **Carrier Distance Engine** displaying yards with canonical 4-stage color grading (≤30y Green, 31–50y Yellow, 51–80y Orange, >80y Red).
- **ClassicAPI Slot-Batching Aura Tracking**: Displays carrier debuff stacks (*Focused Assault* / *Brutal Assault*) in linear $O(n)$ time.

### 5. Interactive Chat Announcements
- `CTRL + Left-Click` on a timer row (AB/AV node, WSG flag, Spirit Healer, or Queue) to announce its displayed countdown to battleground chat while in a battleground.
- Drag an AB/AV/WSG timer by its header; objective rows remain dedicated click targets.

### 6. Enemy Target Frames (BattlegroundTargets)
- **Compact PvP Roster Display**: Automatically displays live enemy target frames for 10v10 (WSG), 15v15 (AB / Thorn Gorge), and 40v40 (AV) with independent scaling, dimensions, and font sizes.
- **Authoritative Flag Carrier Visuals**: Renders authentic 32x32 transparent flag icons directly on the enemy carrier row in Warsong Gulch, synchronized in real time with `AutoBG_FC`.
- **Observed Stealth Tracking**: Tracks Stealth, Prowl, Vanish, Shadowmeld and supported invisibility effects through structured unit auras, ClassicAPI successful-cast events, SuperWoW raw-GUID cast events and exact-name English combat messages. A BG option controls the popup and sound; row stealth icons/text remain always enabled.
- **Roster Sorting**: Bounded insertion sort over active enemies with class color-coding and exact SuperWoW targeting (`TargetUnit(guid)`).

### 7. Open-World Enemy Radar (Spy)
- **Real-Time Hostile Tracking**: Detects nearby enemy players in the open world using ClassicAPI `UNIT_SPELLCAST_SUCCEEDED`, SuperWoW `UNIT_CASTEVENT`, nameplate units, and combat log telemetry.
- **Class and Stealth Icons**: Normal Spy rows show their class icon. An observed stealth/invisibility effect replaces it with the matching spell icon and state label; ending that effect restores the class icon.
- **Stable Nearby List**: New enemies appear at the top; ongoing casts and aura updates refresh their details without reordering existing rows. The display supports up to 20 rows, with 10 shown by default.
- **Audio & Stealth Alerts**: Separate general-enemy and stealth alerts, with the matching stealth/Meld icon. Spy offers two stealth warning modes: nearby confirmation (default) or a warning when a stealth cast/combat-log event is received. Repeated observations of the same active stealth state do not replay the alert.
- **Compact Empty Header**: With no enemies, the list collapses to 96x24 pixels at 100% scale. Populated rows retain their readable width. The existing Spy Scale and Auto-Hide settings remain available.
- **Battleground Display**: The nearby list hides in BGs. The shared stealth popup remains available through Enemy Frames > Stealth alerts in BGs.

---

## Current UI and PvP behavior

AB and AV objective timers use compact 22-pixel rows with flat, muted faction fills, centered warm-white names and a separate countdown. The fill covers the row height; the final ten seconds use amber countdown text. Drag the battleground heading to reposition; Ctrl-click a row to announce its timer.

Enemy-frame health bars, flag-carrier icons and stealth icons/text are always enabled. Each 10v10, 15v15 and 40v40 bracket always saves its own position; existing shared positions migrate once. The enable checkbox names the selected bracket. Separate flag-carrier panels use compact 220x42 dimensions.

Enemy rows now default to 210px width, 12px names and 26px height (40-player lists use 11px / 20px). Objective panels and Spy use larger text; flag-carrier cards are wider. Old default enemy dimensions migrate once, preserving custom dimensions, scales and saved positions. Adjust each bracket under /abg targets; use /abg test to preview.

Detected enemy PvP trinket uses start a **180-second estimate**, per the deployment requirement. Duplicate cast/chat observations do not restart it. Generic immunity names and unsubstantiated compatibility IDs no longer trigger it. An icon without a countdown means no active tracked cooldown, not proof of readiness.

In `/abg spy`, **Stealth alerts outside BGs** enables the popup and sound. **Nearby stealth alerts only** is on by default, including for existing saved settings: it requires an exact-GUID hostile unit currently loaded and visible to the client, a current stealth aura, confirmed distance within 10 yards and clear line of sight. Spy retries a pending observation, including a cast-first entry with no initial target/nameplate token. Unknown range or line of sight stays silent; the 10-yard radius is an addon notification policy, not the server's stealth-detection formula. Turn **Nearby stealth alerts only** off for Spy-style warnings when a supported stealth cast or English combat-log event reaches the client, even at a distance or without a currently visible unit. Neither mode can discover an enemy from an event the client never receives. BG alerts retain their separate nearby-confirmation rule. The general enemy sound toggle controls a separate sound.

Successful Stealth/Vanish casts also update through ClassicAPI's instant-cast event path. A short 0.5-second settling window protects a new cast from an early empty aura snapshot; existing tickers recheck it once. A fresh cast supersedes an old death flag, while unavailable aura/health data does not erase the indicator. Explicit fades, melee activity and visible death remain authoritative. Row/alert clicks validate a cached GUID before using it, with an exact-name lookup when it is absent or mismatched.

Only client-observed stealth can be reported. AutoBG cannot discover an unseen enemy merely because they are stealthed. An unavailable unit does not clear the last observed state; visible aura absence, matching fade messages, melee activity or known effect expiry can clear it.

The code and mocked Lua regressions are checked; the new cast-first detection path still requires in-game duel verification, as do BG event delivery, sound playback and rendering. See [audit and test checklist](docs/AUTOBG_REVIEW_2026-09-26.md) and the [stealth/Spy regression review](docs/STEALTH_SPY_REVIEW_2026-09-27.md).

## ⌨️ Commands & Shortcuts

| Command / Shortcut | Description |
| :--- | :--- |
| `/abg` | Toggle options configuration panel (General tab) |
| `/abg targets` / `/abg bgt` | Open options directly to Enemy Frames tab |
| `/abg spy` | Open options directly to Spy radar tab |
| `/abg timers` | Open options directly to Timers & FC tab |
| `/abg test` | Toggle test mode for all frames and timers |
| `/abg q [wsg\|ab\|av\|tg\|all]` | Quick-queue for a specific BG or all 3 BGs |
| `/abg a` | Toggle Auto-Accept queue pop |
| `/abg delay <sec>` | Set Auto-Accept delay countdown (0–120s) |
| `/abg j` | Toggle Auto-Rejoin on battleground exit |
| `/abg l` | Toggle Auto-Leave on match conclusion |
| `/abg r` | Toggle Auto-Release spirit on death |
| `/abg c` | Toggle Scoreboard class colors |
| `/abg efc` / `/abg tar` | Target enemy flag carrier via GUID / exact name |
| `/abg ffc` | Target friendly flag carrier |
| `/abg focus` | Focus enemy flag carrier via SuperWoW `FocusUnit` |
| `/abg msg` | Toggle chat status notifications |
| `/abg s` / `/abg f` | Toggle sound alerts / taskbar flashing |
| `/abg reset` | Reset all configuration and frame positions to defaults |
| `/bgt` | Open Enemy Frames configuration (BattlegroundTargets alias) |
| `/bgt test [10\|15\|40]` | Toggle enemy target frames preview for bracket |
| `/bgt spy` | Toggle open-world Spy radar test preview |
| `/bgt reset` | Reset enemy target frames and Spy positions |
| `Left-Click` on FC / Target | Target player via GUID / exact whole-name |
| `Right-Click` on FC / Target | Set player as focus via SuperWoW `FocusUnit` |
| `CTRL + Left-Click` on Timer | Broadcast countdown to Battleground chat |
| `Left-Click Drag` on Objective Timer Header | Move and persist the AB/AV/WSG timer frame position |

---

## 📦 Installation & Engine Prerequisites

### Prerequisites
1. **World of Warcraft 1.12.1** (Build 5875).
2. **Required:** [ClassicAPI v1.15.15+](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`).
3. **Required:** [SuperWoW v2.2+](https://github.com/balakethelock/SuperWoW) (upstream distributes `SuperWoWhook.dll` and `SuperWoWlauncher.exe`).
4. **Optional:** [UnitXP SP3](https://codeberg.org/konaka/UnitXP_SP3) (`UnitXP_SP3.dll`); install it for additional carrier telemetry, not for Spy stealth warnings.

### Step-by-Step Installation
1. Clone or download the repository into your WoW AddOns directory:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
2. Verify that `AutoBG.toc` is located directly at:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/AutoBG.toc
   ```
3. Install and enable the required DLLs using their upstream instructions, then launch WoW through the configured loader or SuperWoW launcher. Restart the client after any DLL update.
4. Ensure **AutoBG** is checked in the character selection AddOn screen. Type `/abg` to open settings, or `/abg spy` to open Spy directly.
5. If AutoBG reports a missing ClassicAPI or SuperWoW dependency in chat, check that both DLLs loaded and that ClassicAPI is at least v1.15.15. UnitXP is not required.

### Spy duel check and issue reports
`/abg spy` opens the Spy settings. **Test Stealth** plays the sound sample; **Test Spy** shows a preview. Neither tests live detection. For a live check, duel a same-faction druid in both modes. With **Nearby stealth alerts only** on, a distant Prowl event may label a row but should not warn; approaching within 10 yards with clear line of sight and an active Prowl aura should warn once. With it off, a received Prowl cast or combat-log event should warn once even at a distance. Have the druid leave and re-enter Prowl to test a second episode. If behavior differs, report the selected mode, whether the Spy row showed PROWL, the exact event/log text if available, target/nameplate visibility, approximate distance, Lua errors and ClassicAPI/SuperWoW versions.

---

## 📜 Changelog

### v2.0.0
- **Major Architecture Modernization**: Complete multi-phase architectural overhaul across all 6 runtime modules adhering strictly to modern enhanced engine standards for World of Warcraft 1.12.1 Enhanced Client stacks.
- **Core Runtime & Primaries Modernization (Phase 1)**:
  - Standardized `Spy_OnEvent` on ClassicAPI modern positional dispatch and aligned SuperWoW `UNIT_CASTEVENT` argument mapping (`casterGUID`, `targetGUID`, `eventType`, `spellId`, `castDuration`).
  - Implemented direct GUID focus assignment (`FocusUnit(guid)`) across Targets rows and Flag Carrier HUD cards, eliminating programmatic target swapping.
  - Fixed countdown row expiration compaction, eliminating ghost rows and bar stacking artifacts.
  - Converted enemy PvP trinket cooldown tracking to zero-allocation memory recycling via native C++ `table.wipe`.
- **Hot-Path Optimization & Event Gating (Phase 2)**:
  - Implemented high-performance lifecycle gating for enemy target frames, suppressing open-world event overhead while guaranteeing immediate activation upon battleground entry.
  - Cached battleground zone and instance state synchronously on entry and zone events, eliminating repeated string lookups in recurring tickers.
  - Removed transient table allocations from Arathi Basin score polling and mathematical projection calculations.
  - Suspended idle trinket tickers when no active cooldowns are being tracked.
  - Optimized Spy rendering by decoupling frequent elapsed time text updates from structural roster redraws.
- **Authoritative Targeting & Telemetry (Phase 3A)**:
  - Eradicated legacy 2006 map-coordinate approximations and `SetMapToCurrentZone` side effects in favor of pure 3D Euclidean distance calculations and native UnitXP telemetry.
  - Added native GUID-backed mouseover support (`SetMouseoverUnit(guid)`) across enemy target rows.
  - Centralized canonical class colors in `AutoBG_CLASS_COLORS` and corrected Shaman coloration to authentic blue (`#0070DE`), exempting it from vanilla pink `RAID_CLASS_COLORS` overwrites.
- **Unified Position Persistence & State Migration (Phase 3B)**:
  - Centralized frame coordinates under `AutoBG_Settings.Positions` across all modules.
  - Built automatic, non-destructive migration on `ADDON_LOADED` for legacy `Targets.pos` and `Spy.posX/posY` state.
  - Removed cross-module position state corruption (Spy writing into Targets).
  - Preserved independent bracket positioning (`10`, `15`, `40`) with clean resets that never resurrect legacy keys.
- **Engine Baseline Reconciliation & Polish (Phase 4)**:
  - Enforced `MIN_CLASSIC_API = 11515` (`ClassicAPI v1.15.15+`) and `SUPERWOW_VERSION` startup guards across all 6 modules.
  - Aligned runtime requirements with actual API consumption, cleanly designating UnitXP SP3 as optional and eliminating unconsumed legacy claims.
  - Replaced technical developer stack startup output with clean, player-friendly notification text (`v2.0.0 loaded`).
  - Passed complete static linter audit with 0 errors and 0 warnings.

### v1.7.0
- **Consolidation of BattlegroundTargets & AutoBG**: Merged BattlegroundTargets (`AutoBG_Targets.lua`) and Open-World Spy (`AutoBG_Spy.lua`) natively into AutoBG, creating a single, all-in-one competitive PvP command center.
- **De-duplicated Flag Carrier Logic**: `AutoBG_FC` is the sole authoritative state machine for Warsong Gulch flags, notifying `AutoBG_Targets` directly without redundant chat regexes or duplicate event registrations.
- **Authentic WSG Flag Icons**: Displays real 32x32 transparent flag textures on target frame carrier rows (Red Horde flag on Alliance FC; Blue Alliance flag on Horde FC).
- **Unified 4-Tab Control Panel (`AutoBG_Options.lua`)**: Replaced separate options dialogs with a modern 4-tab interface (`[General]`, `[Timers & FC]`, `[Enemy Frames]`, `[Spy]`) with bracket selectors and global action buttons (`[Test All Frames]`, `[Reset Positions]`, `[Close]`).
- **Full Backward Compatibility**: Added `/bgt` and `/battlegroundtargets` aliases, cross-module tab routing (`AutoBG_OpenOptions("targets")`), and native settings profiles under `AutoBG_Settings`.
- **Enhanced Engine Compliance**: Added ClassicAPI and SuperWoW startup guards and dual-mode event dispatch for the supported runtime.

### v1.6.0
- **Warsong Flag Carrier Faction Correction**: Resolved architectural flag carrier inversion where Horde and Alliance carriers were swapped across frames and map coordinates; accurately binds carrier identity, flag tokens, and frame visual assets.
- **SuperWoW Native Focus & Hybrid Targeting (AP-08 & AP-03)**: Added native right-click focus assignment (`FocusUnit(guid)`) with exact whole-name fallback on Flag Carrier frames; added `/abg efc`, `/abg ffc`, and `/abg focus` macro commands.
- **Nameplate Unit Token Scanning**: Extended `SCAN_UNITS` with `nameplate1`..`nameplate30` for instant detection of hostile flag carriers as soon as their nameplate renders, even before any raid member targets them.
- **Zero-GC Objective Ticker (Tier 2/3)**: Eliminated 90 heap allocations/second inside the 10 Hz `UpdateAllTimers` ticker by converting test row definitions into Tier 0 static constants.
- **Deterministic Bounded Objective Sorting (Section 10)**: Implemented zero-closure bounded insertion sort for active contested nodes in AB and AV; objectives closest to expiring or capping always render at the top of the HUD.
- **Anti-Deadzone Fix on Respawn Bar (Rule C3 / AP-09)**: Injected `bar:EnableMouse(false)` on `AutoBG_RespawnFrame` StatusBar, ensuring 100% dragging and announcement click passthrough.
- **Deterministic Layout Engine (Rule C1)**: Migrated Options Panel checkboxes and controls from fragile 15-element cascading anchor chains to deterministic panel-relative coordinates.
- **Auto-Accept & Zoning Stabilization**: Deduplicated instant auto-accept popup handling to eliminate double accept packets and redundant chat prints; stabilized `AutoRejoin` transition delay to 1.2s across loading screens.
- **Thorn Gorge Suite Alignment**: Added `"TG"` abbreviation and estimated wait time tooltip integration (`GetBattlefieldEstimatedWaitTime`) to queue frames.

### v1.5.0
- **Engine Startup Guard Enforcement**: Upgraded engine dependency guards across all 4 module files (`AutoBG.lua`, `AutoBG_Options.lua`, `AutoBG_Timers.lua`, `AutoBG_FC.lua`) to strictly enforce `MIN_CLASSIC_API = 11508` (`v1.15.8+`) and `SUPERWOW_VERSION` (`v2.2+`).
- **Battleground Suite & Spatial Telemetry Audit**: Re-verified Thorn Gorge queue integration, zero-allocation pre-allocated static unit buffers, and hardware 3D Euclidean distance calculations.

### v1.4.0
- **Native `hooksecurefunc` Architecture**: Replaced all remaining legacy 2006 function overwrites (`WorldStateScoreFrame_Update`, `StaticPopup_Show`, `ShapeshiftBar_Update`) with non-destructive, native C++ `hooksecurefunc` calls (Rule B10), completely eliminating hook collisions with other UI addons.
- **Universal `_G` Table Indexing**: Eradicated all occurrences of legacy `getglobal(...)` across core and options modules in favor of direct `_G[...]` table indexing.
- **Zero-GC Unit Arrays**: Pre-allocated static unit lists (`SCAN_UNITS`) directly during initialization without runtime `table.insert` overhead (Rule D1 & D2).
- **Guarded 3D Spatial Telemetry**: Hardened `UnitPosition` coordinate queries with explicit numerical validation, strictly adhering to Rule B9.
- **Pure English Standard (Rule F9 & H2)**: Verified complete elimination of multi-locale cruft and foreign language strings.

### v1.3.0

- **ClassicAPI Linear Slot-Batching**: Integrated `C_UnitAuras.GetAuraSlots` and `GetAuraDataBySlot` to track Warsong flag carrier damage amplification debuffs (*Focused Assault* / *Brutal Assault*) in linear $O(n)$ time.
- **Rule C8 Mouse Passthrough**: Applied `:EnableMouse(false)` across all child health bars, textures, and font strings inside FC unit cards, guaranteeing 100% click reliability.
- **SuperWoW Hybrid Targeting & Mouseover**: Upgraded FC frame targeting to prioritize `TargetUnit(guid)` with `TargetByName(name, true)` fallback, and enabled native `SetMouseoverUnit` support for mouseover macros.
- **Eradicated Legacy Map Approximations**: Removed 2006 manual map coordinate trigonometry and magic multipliers (`(px - fx) * 515`) in favor of direct 3D Euclidean distances and native `UnitXP("distance", unit)`.
- **Zero-GC Pre-allocated Queue Buffers**: Pre-allocated static arrays and `table.wipe` recycling in `AutoBG_QueueAllBGs`, eliminating heap churn during multi-queue operations.
- **Modern Hook Architecture**: Replaced manual function hooks with `hooksecurefunc` for clean compatibility with other stance-modifying addons.
- **Universal Engine Guard**: Added ClassicAPI and SuperWoW startup checks across the then-current modules.

### v1.2.0
- **Zero-GC Scan Loop Optimizations**: Pre-allocated static `RAID_UNITS` arrays across all modules and eliminated anonymous closure allocations in recurring scan tickers.
- **Native Memory Operations**: Integrated native C++ `table.wipe` for instant table clearing across timer and objective collections.
- **Taskbar Window Alerts**: Added native `FlashClientIcon()` alerting on match end and battleground queue pops.
- **Modern Lua 5.1 AST Syntax**: Modernized table length checks and modulo math to `#` and `%` syntax.

### v1.1.0
- **Consolidated Timer Pipeline**: Replaced legacy 2006 timer loops with unified `AutoBG_TimerAfter` and native `C_Timer`.
- **Warsong FC HUD**: Integrated UnitXP SP3 dynamic distance grading and SuperWoW target lock.

---

## 📄 License & Community

- **Author & Maintainer**: **[Fostercare5988](https://github.com/Fostercare5988)**
- **GitHub Repository**: [https://github.com/Fostercare5988/AutoBG](https://github.com/Fostercare5988/AutoBG)
- **License**: MIT License - See [LICENSE](LICENSE) for details.

Enemy frames can always be moved using the visible Drag to move header. Objective timers can be dragged by their rows or heading; the AB forecast also moves with ordinary left-drag. No preview or Shift key is required. Compact objective text uses the established Friz font and bundled bar texture; in-client rendering must be verified after reload.

Objective progress fills animate smoothly between timer updates. Under Timers & FC, Countdown Appearance controls AB/AV/WSG bar width (180-420), height (18-32), scale (60-150%) and opacity (20-100%). These settings save per character and apply to active groups and the timer preview. Text stays on whole seconds; preview samples remain static. Queue, resurrection and flag-carrier panels keep their separate presentation.
