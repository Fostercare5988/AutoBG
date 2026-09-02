# AutoBG

[![Version](https://img.shields.io/badge/Version-1.2.0-blue.svg)](https://github.com/Fostercare5988/AutoBG/releases)
[![Interface](https://img.shields.io/badge/Interface-1.12.1%20(Build%205875)-orange.svg)](https://github.com/Fostercare5988/AutoBG)
[![Engine](https://img.shields.io/badge/Engine-ClassicAPI%20%7C%20SuperWoW%20%7C%20NamPower%20%7C%20UnitXP%20%7C%20DXVK-green.svg)](https://github.com/Fostercare5988/AutoBG)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Fostercare5988/AutoBG)

**AutoBG v1.2.0** is a high-performance, zero-latency PvP automation and battleground intelligence engine engineered natively for **World of Warcraft 1.12.1** on the **Enhanced Client Extension Stack** (**ClassicAPI**, **SuperWoW 2.2+**, **NamPower 4.6.2+**, **UnitXP SP3**, and **DXVK**) created and maintained by **Fostercare5988**.

---

## 📸 Preview

![AutoBG Overview](preview.jpg)

---

## 🚀 Engine Architecture & Performance

- **⏱️ ClassicAPI C++ Native Timers**:
  - Direct hardware timer scheduling via `C_Timer.After()` and `C_Timer.NewTicker()`, completely bypassing legacy Lua `OnUpdate` frame polling loops and eliminating GC churn.
- **⚡ SuperWoW 2.2+ C++ Native Engine**:
  - OS-level `FlashClientIcon()` taskbar notifications and `SetClientWindowForeground()` window focus on queue pops.
  - Exact whole-name resolution via `TargetByName(name, true)` for 1-click Flag Carrier targeting.
  - High-precision 3D coordinate delta calculations (`UnitPosition`) for cross-map flag carrier tracking.
- **🏎️ NamPower 4.6.2+ Event Pipeline**:
  - Microsecond-precision event queueing and zero-latency packet dispatching.
  - Frame-0 execution for auto-queueing, match exits, and objective updates with 0ms delay.
- **🎯 UnitXP SP3 Health & Distance Engine**:
  - Real-time `UnitXP("distance", unit)` calculations with dynamic 4-stage range coloring (`≤30 yd` green, `31–50 yd` yellow, `51–80 yd` orange, `>80 yd` red).
  - True uncapped enemy HP numbers (`3840 (85%)`) via `UnitXP("health", unit)` & `UnitXP("maxhealth", unit)`.
- **🌱 Zero-GC Memory Footprint & DXVK Smoothness**:
  - Pre-allocated static unit lookup arrays (`RAID_UNITS`, `PARTY_UNITS`) to eliminate string concatenation heap allocations during recurring scan loops.
  - Decoupled delta-time rendering optimized for high-refresh 144Hz+ display engines under DXVK.

---

## ⚡ Core Features

### 1. Automation & Queue Engine
- **Instant Match Exit**: Calls `LeaveBattlefield(0)` immediately upon match conclusion.
- **0ms Instant Auto-Rejoin**: Automatically re-queues into the same BG (AB, WSG, AV, TG) on zoning out.
- **1-Click Quick-Queue**: Queue into any battleground from anywhere in the world via slash command (`/abg q ab`, `/abg q wsg`, `/abg q av`, `/abg q tg`) or macro button (`/click AutoBG_QuickQueueButton`).
- **Auto-Accept & Configurable Delay**: Instant entry (0s) or configurable countdown slider (`0–70s`, up to `120s` via command).
- **Smart Spirit Release**: Auto-releases spirit inside battlegrounds while preserving Soulstones and Reincarnation (Ankh).

### 2. Objective & Base Timers
- **Arathi Basin**: 60s node capture countdowns with faction color-coding (Horde / Alliance).
- **Alterac Valley**: 300s bunker, tower, and graveyard capture countdowns.
- **Warsong Gulch**: 23s flag respawn countdowns (zone-isolated).
- **Match Gates**: Universal pre-match countdowns (120s, 60s, 30s, 15s).

### 3. Server-Synchronized Spirit Healer Engine
- Live 30-second Spirit Healer wave synchronization aligned with `GetAreaSpiritHealerTime()`, `PLAYER_UNGHOST`, and `PLAYER_ALIVE`.
- Color-graded progress bar: Green (>10s) -> Yellow (5-10s) -> Orange (2-5s) -> Red (<=2s).

### 4. Warsong Flag Carrier (FC) HUD
- Clickable unit frames for friendly and enemy carriers with 1-click SuperWoW exact target lock.
- Live raw HP & percentage via **UnitXP SP3** with class-color resolution.
- Live **EFC Distance Tracker** (yards) with dynamic color gradient.

### 5. Interactive Chat Announcements
- `CTRL + Left-Click` any timer (AB/AV node, WSG flag, Spirit Healer, or Queue) to broadcast its countdown into **Battleground chat** (or Party/Raid).

---

## ⌨️ Commands & Shortcuts

| Command / Action | Description |
| :--- | :--- |
| `/abg` | Open options configuration panel |
| `/abg q [wsg\|ab\|av\|tg]` | Quick-queue for a specific BG (or last played if blank) |
| `/abg a` | Toggle Auto-Accept queue pop |
| `/abg delay <sec>` | Set Auto-Accept delay countdown (0–120s) |
| `/abg j` | Toggle Auto-Rejoin on battleground exit |
| `/abg l` | Toggle Auto-Leave on match conclusion |
| `/abg r` | Toggle Auto-Release on death |
| `/abg c` | Toggle Scoreboard class colors |
| `/abg msg` | Toggle chat status notifications |
| `/abg s` / `/abg f` | Toggle sound alerts / taskbar flashing |
| `/abg stealth` | Toggle Stealth & Stance bar suppression |
| `/abg test` | Toggle test mode to reposition HUD frames |
| `/abg reset` | Reset all configuration and frame positions |
| `CTRL + Left-Click` on Timer | Broadcast countdown to Battleground chat |
| `Left-Click Drag` on Frame | Move and save frame position |

---

## 📦 Installation & Requirements

1. **Requirements**:
   - **World of Warcraft 1.12.1** (Build 5875).
   - [**ClassicAPI**](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`).
   - [**SuperWoW**](https://github.com/balakethelock/SuperWoW) (`SuperWoW.dll` v2.2+).
   - [**NamPower**](https://github.com/Emyrk/nampower) (`nampower.dll` v4.6.2+).
   - [**UnitXP SP3**](https://codeberg.org/konaka/UnitXP_SP3) (`UnitXP_SP3.dll`).
   - [**DXVK**](https://github.com/doitsujin/dxvk) & [**VanillaFixes**](https://github.com/hannesmann/vanillafixes).
2. **Installation**:
   - Place the `AutoBG` folder into:
     ```text
     World of Warcraft/Interface/AddOns/AutoBG/
     ```
   - Ensure `AutoBG.toc` is directly inside `Interface/AddOns/AutoBG/`.
   - Enable **AutoBG** in the AddOn list at character selection.

---

## 📜 Changelog

### v1.2.0
- **Zero-GC Scan Loop Optimizations**: Pre-allocated static `RAID_UNITS` arrays across all modules and eliminated anonymous function closure allocations in the 6.6Hz Flag Carrier scanning ticker.
- **Native Memory Operations**: Integrated native C++ `table.wipe` for instant garbage-free table resets across timer and objective collections.
- **Engine Stack Standardization**: Upgraded startup dependency guard to inspect `CLASSIC_API_VERSION` and `SUPERWOW_VERSION` globals.
- **Modern Lua 5.1 AST Syntax**: Modernized table length checks and modulo math to `#` and `%` syntax via ClassicAPI source-rewriter.
- **Taskbar Window Alerts**: Added native `FlashClientIcon()` alerting on match end and battleground queue pops.
- **Standard Open-Source Release**: Standardized TOC metadata (`X-Category`, `X-Website`) and comprehensive documentation under Master System Prompt Rule H5.

### v1.1.0
- **Consolidated Timer Pipeline**: Replaced legacy 2006 timer loops with unified `AutoBG_TimerAfter` and native `C_Timer`.
- **Warsong FC HUD**: Integrated UnitXP SP3 dynamic distance grading and SuperWoW target lock.

---

## 📄 License & Authorship

- **Author & Maintainer**: **[Fostercare5988](https://github.com/Fostercare5988)**
- **License**: MIT License - See [LICENSE](LICENSE) for details.
