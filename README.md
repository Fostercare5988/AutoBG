# AutoBG

[![Version](https://img.shields.io/badge/version-1.0.1-blue.svg)](https://github.com/Fostercare5988/AutoBG/releases)
[![Interface](https://img.shields.io/badge/interface-1.12.1%20%2F%20OctoWOW-orange.svg)](https://github.com/Fostercare5988/AutoBG)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Fostercare5988/AutoBG)

High-performance, zero-latency PvP automation and battleground intelligence engine engineered natively for World of Warcraft 1.12.1 on the **OctoWoW Engine Stack** (**SuperWoW 2.2+**, **NamPower 4.6.2+**, **UnitXP SP3**, **DXVK 3.0.2+**, and **VanillaFixes**).

---

## 📸 Preview

![AutoBG Overview](preview.jpg)

---

## 🚀 Engine Architecture & Performance

- **⚡ SuperWoW 2.2+ C++ Native Engine**:
  - Direct hardware timer scheduling via `C_Timer.After()`, bypassing legacy Lua `OnUpdate` queues.
  - OS-level `FlashClientIcon()` taskbar notifications and `SetClientWindowForeground()` window focus on queue pops.
  - Exact whole-name resolution via `TargetByName(name, true)` for 1-click Flag Carrier targeting.
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
- **0ms Instant Auto-Rejoin**: Automatically re-queues into the same BG (AB, WSG, AV, TG) on zoning out via OctoWoW's Battleground Finder.
- **1-Click Quick-Queue**: Queue into any battleground from anywhere in the world via slash command (`/abg q ab`, `/abg q wsg`, `/abg q av`, `/abg q tg`) or macro button (`/click AutoBG_QuickQueueButton`).
- **Auto-Accept & Configurable Delay**: Instant entry (0s) or configurable countdown slider (`0–70s`, up to `120s` via command).
- **Smart Spirit Release**: Auto-releases spirit inside battlegrounds while preserving Soulstones and Reincarnation (Ankh).

### 2. Objective & Base Timers
- **Arathi Basin**: 60s node capture countdowns with faction color-coding (Horde / Alliance).
- **Alterac Valley**: 300s bunker, tower, and graveyard capture countdowns.
- **Warsong Gulch**: 23s flag respawn countdowns (zone-isolated).
- **Match Gates**: Universal pre-match countdowns (120s, 60s, 30s, 15s).

### 3. Server-Synchronized Spirit Healer Engine
- Live 30-second Spirit Healer wave synchronization aligned with `GetBattlefieldInstanceRunTime()`, `GetAreaSpiritHealerTime()`, and `PLAYER_UNGHOST`.
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

## 📦 Installation

1. Download the latest release from the [Releases](https://github.com/Fostercare5988/AutoBG/releases) page.
2. Place the `AutoBG` folder into:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
3. Ensure `AutoBG.toc` is directly inside `Interface/AddOns/AutoBG/`.
4. Enable **AutoBG** in the AddOn list at character selection.

---

## 📄 License & Authorship

- **Author & Maintainer**: **[Fostercare5988](https://github.com/Fostercare5988)**
- **License**: MIT License - See [LICENSE](LICENSE) for details.
