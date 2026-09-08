# AutoBG

[![Interface: 1.12.1](https://img.shields.io/badge/Interface-1.12.1%20(5875)-orange.svg)](https://github.com/Fostercare5988/AutoBG)
[![Version: 1.7.0](https://img.shields.io/badge/Version-1.7.0-blue.svg)](https://github.com/Fostercare5988/AutoBG/releases)
[![ClassicAPI: v1.14.0+](https://img.shields.io/badge/ClassicAPI-v1.14.0+-green.svg)](https://github.com/brues-code/ClassicAPI)
[![SuperWoW: v2.2+](https://img.shields.io/badge/SuperWoW-v2.2+-brightgreen.svg)](https://github.com/balakethelock/SuperWoW)
[![NamPower: v4.6.3+](https://img.shields.io/badge/NamPower-v4.6.3+-blueviolet.svg)](https://github.com/Emyrk/nampower)
[![UnitXP: SP3](https://img.shields.io/badge/UnitXP-SP3-teal.svg)](https://codeberg.org/konaka/UnitXP_SP3)
[![DXVK: Vulkan](https://img.shields.io/badge/DXVK-Vulkan-red.svg)](https://github.com/doitsujin/dxvk)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**AutoBG v1.7.0** is an enterprise-grade, zero-latency PvP automation and battleground intelligence engine engineered natively for **World of Warcraft 1.12.1 (Build 5875)**. Built directly atop the modern **Enhanced Client Extension Stack** (**ClassicAPI v1.14.0+**, **SuperWoW v2.2+**, **NamPower v4.6.3+**, **UnitXP SP3**, and **DXVK**), AutoBG eliminates 2006-era polling loops, garbage-collection hitches, and imprecise coordinates to deliver instant, hardware-level PvP responsiveness.


Created and actively maintained by **[Fostercare5988](https://github.com/Fostercare5988)**.

---

## 📸 Preview

![AutoBG Overview](preview.jpg)

---

## 🚀 Engine Architecture & Performance

AutoBG is engineered around strict low-level system integration:

| Engine Component | Minimum Version | Architectural Role & Implementation |
| :--- | :--- | :--- |
| **ClassicAPI** | `v1.14.0+` | C++ hardware timers (`C_Timer.After`), modern linear $O(n)$ slot-batching aura queries (`C_UnitAuras.GetAuraSlots` / `GetAuraDataBySlot`), native `hooksecurefunc`, and source-rewritten Lua 5.1 syntax. |
| **SuperWoW** | `v2.2+` | Direct memory state access, exact-name targeting fallback (`TargetByName(name, true)`), direct GUID targeting (`TargetUnit(guid)`), and native hover state tracking (`SetMouseoverUnit`). |
| **NamPower** | `v4.6.3+` | Microsecond-precision combat pipeline and frame-0 event dispatching. |
| **UnitXP** | `SP3` | High-precision raw 3D Euclidean distance calculations (`UnitXP("distance", unit)`), line-of-sight tracking, and OS taskbar alert notifications (`FlashClientIcon`). |
| **DXVK** | `Latest` | Decoupled high-refresh frame pacing with zero garbage collection heap churn. |

### Elimination of 2006 Legacy Techniques
- **Zero OnUpdate Polling**: Frame-based `OnUpdate` polling loops are eradicated; all periodic tasks run on C++ hardware tickers at optimal intervals (6.6 Hz for FC tracking, 10 Hz for objective timers).
- **Zero-GC Pre-allocated Buffers**: Static unit arrays (`RAID_UNITS`, `PARTY_UNITS`) and pre-allocated queue lists recycle existing heap tables via native `table.wipe`, avoiding recurring garbage-collection freezes in large 40-man Alterac Valley battles.
- **No Map Multiplier Fallbacks**: Eradicated legacy 2006 manual map approximations and magic multipliers (`(px - ux) * 515`) in favor of direct 3D Euclidean distances and native UnitXP measurements.
- **Strict Mouse Passthrough (Rule C8)**: All child frames inside clickable unit cards disable mouse interception (`EnableMouse(false)`), guaranteeing that 100% of the card's visual surface triggers target locks and macro execution.

---

## ⚡ Key Features

### 1. Automation & Queue Engine
- **Instant Match Exit**: Calls `LeaveBattlefield(0)` at frame 0 upon match conclusion.
- **Zero-Latency Auto-Rejoin**: Automatically re-queues into the same battleground (WSG, AB, AV) upon zoning out via Battleground Finder.
- **1-Click Multi-Queue**: Automatically registers for all 3 battlegrounds (Warsong Gulch, Arathi Basin, and Alterac Valley) with sequential queuing.
- **Auto-Accept with Configurable Delay & AFK Guard**: Instant entry (0s) or configurable countdown slider (0–70s, up to 120s via command). Automatically pauses auto-enter and auto-queue operations whenever you are tagged as AFK to prevent deserted debuffs.
- **Smart Spirit Release**: Auto-releases spirit upon death inside battlegrounds while safely preserving active Soulstones and Reincarnation (Ankh).
- **Taskbar Window Flashing**: Direct OS-level notification flashing (`FlashClientIcon`) when queues pop while tabbed out.

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
- **Public Query API**: Exports `AutoBG_GetCarrier(faction)` and `AutoBG_GetCarrierInfo(faction)` for zero-overhead query access by external frames and macros.
- Clickable unit cards for Alliance and Horde flag carriers with **SuperWoW Hybrid Targeting** (`TargetUnit(guid)` with `TargetByName(name, true)` fallback).
- Native SuperWoW mouseover support (`SetMouseoverUnit`) allowing mouseover macros directly over FC cards.
- Real-time uncapped carrier HP and percentage via **UnitXP SP3** with class-color resolution.
- Live **Carrier Distance Engine** displaying yards with canonical 4-stage color grading (≤30y Green, 31–50y Yellow, 51–80y Orange, >80y Red).
- **ClassicAPI v1.14.0+ Slot-Batching Aura Tracking**: Displays carrier debuff stacks (*Focused Assault* / *Brutal Assault*) in linear $O(n)$ time.

### 5. Interactive Chat Announcements
- `CTRL + Left-Click` on any timer row (AB/AV node, WSG flag, Spirit Healer, or Queue) to broadcast its exact countdown into Battleground chat (or Party/Raid).

### 6. Enemy Target Frames (BattlegroundTargets)
- **Compact PvP Roster Display**: Automatically displays live enemy target frames for 10v10 (WSG), 15v15 (AB / Thorn Gorge), and 40v40 (AV) with independent scaling, dimensions, and font sizes.
- **Authoritative Flag Carrier Visuals**: Renders authentic 32x32 transparent flag icons directly on the enemy carrier row in Warsong Gulch, synchronized in real time with `AutoBG_FC`.
- **Stealth & Invisibility Tracking**: Detects enemy Stealth, Prowl, Vanish, and Invisibility casts via SuperWoW `UNIT_CASTEVENT` and combat log packets.
- **Zero-GC Roster Sorting**: Bounded insertion sort over active enemies with class color-coding and exact SuperWoW targeting (`TargetUnit(guid)`).

### 7. Open-World Enemy Radar (Spy)
- **Real-Time Hostile Tracking**: Detects nearby enemy players in the open world using SuperWoW `UNIT_CASTEVENT`, nameplate units, and combat log telemetry.
- **Audio & Stealth Alerts**: Plays alert sounds on enemy detection and a dedicated Prowl sound when an enemy enters stealth nearby.
- **Smart Battleground Suppression**: Automatically hides when zoning into a battleground to keep screen space dedicated to match frames.

---

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
| `/abg stealth` | Toggle Stealth & Stance bar suppression |
| `/abg reset` | Reset all configuration and frame positions to defaults |
| `/bgt` | Open Enemy Frames configuration (BattlegroundTargets alias) |
| `/bgt test [10\|15\|40]` | Toggle enemy target frames preview for bracket |
| `/bgt spy` | Toggle open-world Spy radar test preview |
| `/bgt reset` | Reset enemy target frames and Spy positions |
| `Left-Click` on FC / Target | Target player via GUID / exact whole-name |
| `Right-Click` on FC / Target | Set player as focus via SuperWoW `FocusUnit` |
| `CTRL + Left-Click` on Timer | Broadcast countdown to Battleground chat |
| `Left-Click Drag` on Frame | Move and persist frame position across sessions |

---

## 📦 Installation & Engine Prerequisites

### Prerequisites
1. **World of Warcraft 1.12.1** (Build 5875).
2. [**ClassicAPI v1.14.0+**](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`).
3. [**SuperWoW v2.2+**](https://github.com/balakethelock/SuperWoW) (`SuperWoW.dll`).
4. [**NamPower v4.6.3+**](https://github.com/Emyrk/nampower) (`nampower.dll`).
5. [**UnitXP SP3**](https://codeberg.org/konaka/UnitXP_SP3) (`UnitXP_SP3.dll`).
6. [**DXVK**](https://github.com/doitsujin/dxvk) & [**VanillaFixes**](https://github.com/hannesmann/vanillafixes).

### Step-by-Step Installation
1. Clone or download the repository into your WoW AddOns directory:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
2. Verify that `AutoBG.toc` is located directly at:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/AutoBG.toc
   ```
3. Launch the game using your DLL loader or launcher with ClassicAPI and SuperWoW enabled.
4. Ensure **AutoBG** is checked in the character selection AddOn screen.

---

## 📜 Changelog

### v1.7.0
- **Consolidation of BattlegroundTargets & AutoBG**: Merged BattlegroundTargets (`AutoBG_Targets.lua`) and Open-World Spy (`AutoBG_Spy.lua`) natively into AutoBG, creating a single, all-in-one competitive PvP command center.
- **De-duplicated Flag Carrier Logic**: `AutoBG_FC` is the sole authoritative state machine for Warsong Gulch flags, notifying `AutoBG_Targets` directly without redundant chat regexes or duplicate event registrations.
- **Authentic WSG Flag Icons**: Displays real 32x32 transparent flag textures on target frame carrier rows (Red Horde flag on Alliance FC; Blue Alliance flag on Horde FC).
- **Unified 4-Tab Control Panel (`AutoBG_Options.lua`)**: Replaced separate options dialogs with a modern 4-tab interface (`[General]`, `[Timers & FC]`, `[Enemy Frames]`, `[Spy]`) with bracket selectors and global action buttons (`[Test All Frames]`, `[Reset Positions]`, `[Close]`).
- **Full Backward Compatibility**: Added `/bgt` and `/battlegroundtargets` aliases, cross-module tab routing (`AutoBG_OpenOptions("targets")`), and native settings profiles under `AutoBG_Settings`.
- **Enhanced Engine Compliance**: Enforced strict startup guards (`MIN_CLASSIC_API = 11400`, `SUPERWOW_VERSION`), dual-mode event signatures (Rule C12 / AP-26), and zero-GC combat paths across all modules.

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
- **Engine Startup Guard Enforcement**: Upgraded engine dependency guards across all 4 module files (`AutoBG.lua`, `AutoBG_Options.lua`, `AutoBG_Timers.lua`, `AutoBG_FC.lua`) to strictly enforce `MIN_CLASSIC_API = 11400` (`v1.14.0+`) and `SUPERWOW_VERSION` (`v2.2+`).
- **Battleground Suite & Spatial Telemetry Audit**: Re-verified Thorn Gorge queue integration, zero-allocation pre-allocated static unit buffers, and hardware 3D Euclidean distance calculations.

### v1.4.0
- **Native `hooksecurefunc` Architecture**: Replaced all remaining legacy 2006 function overwrites (`WorldStateScoreFrame_Update`, `StaticPopup_Show`, `ShapeshiftBar_Update`) with non-destructive, native C++ `hooksecurefunc` calls (Rule B10), completely eliminating hook collisions with other UI addons.
- **Universal `_G` Table Indexing**: Eradicated all occurrences of legacy `getglobal(...)` across core and options modules in favor of direct `_G[...]` table indexing.
- **Zero-GC Unit Arrays**: Pre-allocated static unit lists (`SCAN_UNITS`) directly during initialization without runtime `table.insert` overhead (Rule D1 & D2).
- **Guarded 3D Spatial Telemetry**: Hardened `UnitPosition` coordinate queries with explicit numerical validation, strictly adhering to Rule B9.
- **Pure English Standard (Rule F9 & H2)**: Verified complete elimination of multi-locale cruft and foreign language strings.

### v1.3.0

- **ClassicAPI v1.14.0+ Linear Slot-Batching**: Integrated `C_UnitAuras.GetAuraSlots` and `GetAuraDataBySlot` to track Warsong flag carrier damage amplification debuffs (*Focused Assault* / *Brutal Assault*) in linear $O(n)$ time.
- **Rule C8 Mouse Passthrough**: Applied `:EnableMouse(false)` across all child health bars, textures, and font strings inside FC unit cards, guaranteeing 100% click reliability.
- **SuperWoW Hybrid Targeting & Mouseover**: Upgraded FC frame targeting to prioritize `TargetUnit(guid)` with `TargetByName(name, true)` fallback, and enabled native `SetMouseoverUnit` support for mouseover macros.
- **Eradicated Legacy Map Approximations**: Removed 2006 manual map coordinate trigonometry and magic multipliers (`(px - fx) * 515`) in favor of direct 3D Euclidean distances and native `UnitXP("distance", unit)`.
- **Zero-GC Pre-allocated Queue Buffers**: Pre-allocated static arrays and `table.wipe` recycling in `AutoBG_QueueAllBGs`, eliminating heap churn during multi-queue operations.
- **Modern Hook Architecture**: Replaced manual function hooks with `hooksecurefunc` for clean compatibility with other stance-modifying addons.
- **Universal Engine Guard**: Enforced strict dependency checks across all 4 module files for ClassicAPI v1.14.0+ and SuperWoW v2.2+.

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
