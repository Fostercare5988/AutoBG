# AutoBG

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/fostercare123/AutoBG/releases)
[![Interface](https://img.shields.io/badge/interface-1.12.1%20%2F%20OctoWOW-orange.svg)](https://github.com/fostercare123/AutoBG)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/fostercare123/AutoBG)

**AutoBG** is a high-performance, lightweight World of Warcraft addon built from scratch for **Vanilla 1.12.1** and modern enhanced clients (such as **OctoWOW**, **SuperWoW**, and **NamPower**). 

It automates queue handling, provides objective capture timers with faction color-coding, tracks Warsong Gulch Flag Carriers with interactive unit frames, and synchronizes the global 30-second Spirit Healer wave across all battlegrounds.

---

## 📸 Preview

![AutoBG Overview](preview.jpg)

---

## ✨ Features

### ⚡ Queue & Match Automation
- **Instant Auto-Accept**: Automatically accepts and ports into battlegrounds the instant the queue pops (0 ms delay).
- **Automated Battleground Finder Re-Queue**: After finishing a match and loading outside, AutoBG automatically queries the OctoWOW Battleground Finder, selects the matching battleground (**Warsong Gulch**, **Arathi Basin**, **Alterac Valley**, or **Thorn Gorge**), queues for the first available instance, and closes the window seamlessly.
- **Instant Auto-Leave**: Leaves the battleground instance immediately when victory or defeat is declared.
- **Smart Auto-Release**: Instantly releases spirit upon death inside battlegrounds while safely detecting and preserving active **Soulstones** or Shaman **Ankhs**.
- **Alerts & Taskbar Flashing**: Plays triple loud ready-check audio alerts and flashes the Windows taskbar when queues pop.
- **Active Queue Overlays**: On-screen wait timer showing elapsed queue time for active queues.

### ⏱️ Battleground Objective Timers
- **Arathi Basin Nodes**: 60-second capture countdown timers for all 5 bases with faction color-coding (|cFFFF4040Red|r for Horde, |cFF4090FFBlue|r for Alliance).
- **Alterac Valley Bunkers & Graveyards**: 5-minute capture timers for towers, bunkers, and graveyards.
- **Warsong Gulch Timers**: 23-second flag respawn timers and 2-minute / 3-minute powerup buff timers (Speed, Restoration, Berserking).
- **Match Start Countdown**: Universal match countdowns (2m, 1m, 30s, 15s) locked to zone gate openings.

### 👻 Universal Multi-Source Spirit Healer Synchronization Engine
Because all graveyards in Vanilla battlegrounds pulse on the same global 30-second server cycle, AutoBG tracks and locks the wave timer through four independent data sources:
1. **Combat Log Aura Sniffer**: Resets master clock the instant *any* player in range finishes a rez (`Spirit Healing`, `Honorless Target`, `Resurrection Sickness`).
2. **Direct Death Ground-Truth Calibration**: Exact calibration via `GetAreaSpiritHealerTime()` whenever you are a ghost near a spirit guide.
3. **Instance Run-Time Clock Anchor**: Baseline estimate calculated on zone entry via `GetBattlefieldInstanceRunTime() % 30s`.
4. **Visual Urgency Alerts**: Displays countdown in green, shifting to bright yellow at $\le 5\text{s}$ and orange warning at $\le 2\text{s}$.

### 🚩 Warsong Flag Carrier (FC) Tracker
- Interactive on-screen unit frames for both Alliance and Horde flag carriers.
- **One-Click Target**: Left-click the frame to immediately target the enemy or friendly carrier.
- **Class-Colored Names**: Automatic resolution of carrier class from scoreboard and raid caches.
- **Dynamic Health Bar**: Live HP percentage status bar (Green $\rightarrow$ Yellow $\rightarrow$ Red) scanned at 5 Hz.

### 🎨 General UI Tweaks & Quality of Life
- **Scoreboard Class Colors**: Automatically colors player names on the Battleground Scoreboard by class and strips realm suffixes.
- **Hide Default Castbar**: Toggles off Blizzard's default cast bar (ideal for custom castbar addons).
- **Hide Stealth & Stance Bar**: Completely suppresses the default Blizzard `ShapeshiftBarFrame` and its buttons for Rogues (Stealth), Warriors (Stances), Druids (Forms), Priests (Shadowform), and Paladins (Auras).
- **Position Persistence**: All timer and FC frames are draggable (`/abg test`) and save their exact screen coordinates across sessions.

---

## 🚀 Client & DLL Compatibility

AutoBG is written in clean, native Lua 5.0 and is tested for maximum compatibility:
- **SuperWoW**: Full support for unlocked targeting, extended macro attributes, and server packet routing.
- **NamPower / UnitXP / SuperAPI**: Zero conflicts; interoperates cleanly with custom UI unit frames and castbars.
- **ClassicAPI**: Automatic hybrid support—uses `C_Timer.After` if ClassicAPI is loaded, with native internal scheduler fallback.
- **OctoWOW (1.18.1 patch)**: Native integration with the custom Battleground Finder minimap menu and Thorn Gorge.
- **Engine Optimization**: All update loops are throttled (10 Hz for timers, 5 Hz for unit scanner) for zero FPS drops on uncapped high-refresh rate setups.

---

## 🛠️ In-Game Configuration

Type `/abg` or `/autobg` in chat to open the graphical configuration panel.

### Slash Commands

| Command | Description |
| :--- | :--- |
| `/abg` | Open or close the graphical settings window |
| `/abg s` | Toggle Loud Sound Alerts |
| `/abg f` | Toggle Taskbar Flashing |
| `/abg a` | Toggle Auto-Accept Queue Pop |
| `/abg l` | Toggle Auto-Leave BG on match end |
| `/abg j` | Toggle Auto-Rejoin BG via Battleground Finder |
| `/abg r` | Toggle Auto-Release spirit on death |
| `/abg c` | Toggle Scoreboard Class Colors |
| `/abg stealth` | Toggle Hide Stealth / Stance Bar |
| `/abg test` | Toggle Test Mode (unlocks all frames to reposition) |
| `/abg reset` | Reset all settings and frame positions to default |

---

## 📦 Installation

1. Download the latest release from the [Releases](https://github.com/fostercare123/AutoBG/releases) page.
2. Extract the `AutoBG` folder into your World of Warcraft directory:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
3. Ensure the folder name is strictly named `AutoBG` (not `AutoBG-master`).
4. Launch World of Warcraft and enable **AutoBG** in the AddOns menu at character select.

---

## 👤 Author

Developed by **[fostercare123](https://github.com/fostercare123)**.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


