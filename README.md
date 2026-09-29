# AutoBG

PvP automation, battleground objective timers, flag-carrier tracking, enemy unit frames, and open-world stealth alerts for World of Warcraft 1.12.1.

## Features

- **Queue & Match Automation**: 1-click multi-queueing, auto-accept with configurable delay (0–120s) and AFK protection, automatic match exit, automatic re-queue upon departure, and smart spirit release that respects active Soulstones and Reincarnation.
- **Objective Timers**: Precise capture countdowns for Arathi Basin bases and Alterac Valley nodes, flag respawn timers in Warsong Gulch, and synchronized Spirit Healer resurrection wave countdowns.
- **Flag Carrier HUD**: Dedicated Alliance and Horde flag-carrier unit cards showing real-time health, distance, and debuff stacks, with one-click targeting and focus support.
- **Enemy Unit Frames**: Dynamic PvP roster displays for 10v10, 15v15, and 40v40 battlegrounds featuring class coloring, carrier badges, and estimated enemy trinket cooldown tracking.
- **Open-World Radar (Spy)**: Alerts you to nearby hostile players and stealth activations in the open world, with configurable distance thresholds.

## Requirements

- **World of Warcraft 1.12.1** (Build 5875)
- [ClassicAPI v1.15.15+](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`)
- [SuperWoW v2.2+](https://github.com/balakethelock/SuperWoW) (`SuperWoWhook.dll` / `SuperWoWlauncher.exe`)
- *Optional:* [UnitXP SP3](https://codeberg.org/konaka/UnitXP_SP3) (`UnitXP_SP3.dll`) for enhanced carrier distance and raw health reads.

> Note: Completely restart the game client after installing or updating DLLs. `/reload` cannot reload DLLs.

## Installation

1. Copy or clone this repository into your WoW add-on directory:
   ```text
   World of Warcraft/Interface/AddOns/AutoBG/
   ```
2. Verify that `AutoBG.toc` is located directly at `Interface/AddOns/AutoBG/AutoBG.toc`.
3. Launch WoW using the SuperWoW launcher.
4. Ensure AutoBG is enabled on the character selection screen.

## Useful Commands & Controls

| Command / Control | Description |
| :--- | :--- |
| `/abg` | Open options panel |
| `/abg q [wsg\|ab\|av\|tg\|all]` | Queue for specific battlegrounds or all three |
| `/abg a` | Toggle auto-accept queue pop |
| `/abg delay <seconds>` | Set auto-accept countdown delay (0–120s) |
| `/abg j` / `/abg l` / `/abg r` | Toggle auto-rejoin / auto-leave / smart spirit release |
| `/abg efc` / `/abg ffc` | Target enemy or friendly flag carrier |
| `/abg focus` | Set enemy flag carrier as focus |
| `/abg spy` | Open Spy radar settings |
| `/bgt` or `/abg targets` | Open enemy frames configuration |
| `/abg test` | Toggle interface preview mode |
| `/abg reset` | Reset all configuration and frame positions to defaults |
| `Left-Click` on Carrier / Target | Target player |
| `Right-Click` on Carrier / Target | Set focus |
| `Ctrl + Left-Click` on Timer | Announce countdown to Battleground chat |
| `Left-Click Drag` on Header | Reposition objective timers or enemy frames |

## Limitations & Notes

- **Stealth Detection**: Spy can only report what your game client actually receives from the server. It cannot detect players across the map if the server does not send their presence or actions to your client. In the default "Nearby" mode, alerts only sound when a stealthed enemy is within 10 yards with line of sight.
- **Trinket Cooldowns**: Displayed enemy PvP trinket timers are fixed 180-second estimates based on observed trinket activations.

---

For detailed configuration, customization options, and live duel test instructions, see the [User Guide](docs/USER_GUIDE.md). Technical architecture and integration review history are documented under [docs/](docs/).

## License

MIT License. Maintained by [Fostercare5988](https://github.com/Fostercare5988).
