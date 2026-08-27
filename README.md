# AutoBG

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/Fostercare5988/AutoBG/releases)
[![Interface](https://img.shields.io/badge/interface-1.12.1%20%2F%20OctoWOW-orange.svg)](https://github.com/Fostercare5988/AutoBG)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Fostercare5988/AutoBG)

Next-generation 2026 PvP automation and battleground intelligence engine built natively for **SuperWoW 2.2+**, **NamPower**, and **UnitXP SP3**.

---

## 📸 Preview

![AutoBG Overview](preview.jpg)

---

## 🚀 2026 Modern Architecture & DLL Integration

- **⚡ SuperWoW 2.2 C++ Engine**:
  - Native `C_Timer.After()` scheduler replacing slow Lua `OnUpdate` array queues.
  - OS-level `FlashClientIcon()` taskbar notifications on queue pops.
  - Exact `TargetByName(name, true)` substring/whole-name resolution for 1-click Flag Carrier targeting.
- **🏎️ NamPower Event Pipeline**:
  - Microsecond-precision combat event queueing and zero-latency packet dispatching.
  - Frame-0 execution for auto-queueing, match exits, and objective updates with 0ms delay.
- **🎯 UnitXP SP3 Health & Distance Engine**:
  - Direct `UnitXP("health", unit)` and `UnitXP("maxhealth", unit)` hooks providing true raw enemy HP numbers (e.g. `3840 (85%)`) on Flag Carrier unit frames instead of generic percentages.
- **🌱 Pure Memory Footprint**: Minimal heap allocation, stateless mathematical timers via `GetTime()`, zero table garbage accumulation.

---

## ⚡ Core Modules

### 1. Automation & Auto-Queue Engine
- **Instant Match Exit**: Calls `LeaveBattlefield(0)` immediately upon match conclusion detection.
- **0ms Instant Auto-Rejoin**: On zoning out of a battleground, automatically re-queues into the same battleground (AB, WSG, AV, TG) instantly via OctoWOW's Battleground Finder.
- **1-Click Quick-Queue**: Queue from anywhere in the world into any BG using macro buttons or slash commands (`/abg q`, `/abg q ab`, `/abg q wsg`, `/abg q av`, `/abg q tg`).
- **Auto-Accept & Delay Engine**: Confirms queue pop instantly (0s) or after a configurable countdown (0–70s slider, up to 120s via command).
- **Smart Spirit Release**: Auto-releases spirit inside battlegrounds while preserving Soulstones and Reincarnation (Ankh).
- **Audio & Taskbar Alerts**: Ready-check audio triggers and OS taskbar flashing on queue pop.
- **Chat Notifications**: Clean, color-coded system status messages confirming queue entries, pops, and match transitions.

### 2. Objective & Base Timers
- **Arathi Basin**: 60s node capture timers with faction color-coding (Horde / Alliance). Supports all standard combat log aliases (`"the mine"`, `"the mill"`).
- **Alterac Valley**: 300s capture timers for bunkers, towers, and graveyards.
- **Warsong Gulch**: 23s flag respawn timers with faction color-coding (Alliance / Horde). Strictly zone-isolated.
- **Gate Openings**: Universal pre-match countdowns (120s, 60s, 30s, 15s).

### 3. Server-Synchronized Spirit Healer Engine
Synchronizes the global 30-second server resurrection wave with a live visual progress bar:
1. **Server Clock Heartbeat**: Continuous tracking aligned to `GetBattlefieldInstanceRunTime()`.
2. **Ground-Truth Calibration**: Exact phase lock via `GetAreaSpiritHealerTime()` and `PLAYER_UNGHOST`.
3. **Color-Graded Status Bar**: Smooth draining bar transitioning Green (>10s) -> Yellow (5-10s) -> Orange (2-5s) -> Red (<=2s).

### 4. Warsong Flag Carrier (FC) Tracking
- Targetable unit frames for friendly and enemy carriers with 1-click SuperWoW exact target lock.
- Real-time **EFC Distance Tracker** (yards) with dynamic color gradient.
- Live raw HP & percentage via **UnitXP SP3** and class-color resolution.
- 5 Hz background scanner with zero memory churn.

### 5. UI Tweaks
- **Scoreboard Colors**: Class-colored player entries with realm suffix removal.
- **Stance / Stealth Bar**: Suppresses default `ShapeshiftBarFrame` and child action buttons.
- **Draggable Frames**: Position persistence across all timer displays via `/abg test`.

### 6. Interactive Chat Announcements
- **CTRL + Left-Click**: Click any live timer (AB/AV node, WSG flag respawn, Spirit Healer wave, or queue wait time) to instantly broadcast its remaining time into **Battleground chat** (or Party/Raid).

---

## ⌨️ Commands & Macros

### Shortcuts & Click Actions

| Action | Result |
| :--- | :--- |
| `CTRL + Left-Click` on Timer | Broadcast timer countdown to Battleground / Raid chat |
| `Left-Click Drag` on Frame | Move timer frame position (saved across sessions) |

### Slash Commands

| Command | Action |
| :--- | :--- |
| `/abg` | Toggle graphical configuration panel |
| `/abg q` | Queue for last played battleground |
| `/abg q ab` | Queue for Arathi Basin |
| `/abg q wsg` | Queue for Warsong Gulch |
| `/abg q av` | Queue for Alterac Valley |
| `/abg q tg` | Queue for Thorn Gorge |
| `/abg a` | Toggle Auto-Accept queue pop |
| `/abg delay <sec>` | Set Auto-Accept delay (0=instant, up to 120s) |
| `/abg msg` | Toggle chat status notifications |
| `/abg l` | Toggle Auto-Leave on match end |
| `/abg j` | Toggle Auto-Rejoin on zone exit |
| `/abg r` | Toggle Auto-Release on death |
| `/abg c` | Toggle Scoreboard class colors |
| `/abg stealth` | Toggle Stealth / Stance bar suppression |
| `/abg s` | Toggle Sound notifications |
| `/abg f` | Toggle Taskbar flashing |
| `/abg test` | Toggle test mode to reposition all frames |
| `/abg reset` | Reset configuration and frame positions |

### 1-Click Action Bar Macro
```text
/click AutoBG_QuickQueueButton
```
*Or:*
```text
/abg q
```

---

## 📦 Installation

1. Download the latest release from the [Releases](https://github.com/Fostercare5988/AutoBG/releases) page.
2. Place the `AutoBG` directory into:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
3. Verify folder structure: `Interface/AddOns/AutoBG/AutoBG.toc` must be valid.
4. Enable **AutoBG** in the in-game AddOn manager.

---

## 📄 License

MIT License - Developed by **[Fostercare5988](https://github.com/Fostercare5988)**. See [LICENSE](LICENSE) for details.


