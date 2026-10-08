# AutoBG

Battleground queues, objective timers, flag carriers, enemy frames and open-world
enemy alerts for World of Warcraft 1.12.1, build 5875.

## Features

- Queue selected battlegrounds, accept invitations with an optional delay, leave
  completed matches and request the same queue again.
- Show objective, gate, flag-respawn, queue and spirit-healer countdowns.
- Track Warsong flag carriers with health, distance, target and focus controls.
- Show battleground enemy rows, class colors and observed trinket cooldowns.
- Track recent open-world enemies in a compact Spy list, with optional nearby
  stealth warnings and sound suppression.
- Configure everything through four readable settings pages. Drag frame headers
  to move displays; each battleground bracket keeps its own position.

## Requirements

- [ClassicAPI v1.15.15+](https://github.com/brues-code/ClassicAPI)
- [SuperWoW v2.2+](https://github.com/balakethelock/SuperWoW)
- Optional: [UnitXP SP3](https://codeberg.org/konaka/UnitXP_SP3) for supported
  carrier health and distance telemetry.

Start through a launcher that loads the required DLLs. Installing or updating
a DLL requires a full game restart.

## Install

Download [AutoBG v1.0.0](https://github.com/Fostercare5988/AutoBG/releases/tag/v1.0.0)
and extract its `AutoBG` folder into `Interface/AddOns`.
The resulting path must be `Interface/AddOns/AutoBG/AutoBG.toc`.
Enable AutoBG in the character-selection addon list.

## Controls

| Control | Action |
| --- | --- |
| `/abg` | Open settings |
| `/abg timers` | Open timer and carrier settings |
| `/abg targets` or `/bgt` | Open enemy-frame settings |
| `/abg spy` | Open Spy settings |
| `/abg q wsg`, `/abg q ab`, `/abg q av` | Request a battleground queue |
| Left-click an enemy or carrier | Target that player |
| Right-click an enemy or carrier | Focus the verified loaded player |
| Ctrl + left-click a timer | Announce its countdown in battleground chat |
| Drag a display header | Move that display |

## Spy alerts

The list records recent observations received by your client. It is not a count
of everyone within a fixed distance. Five rows display by default; tracking is
capped at 20. Hover a row for further details.

Open-world sounds default to off. **Play enemy alerts** enables them. Alerts
share an eight-second limit; recently seen enemies and repeated stealth episodes
stay quiet. Suppressed alerts are discarded rather than played later.
Battleground stealth warnings have their own setting and the same burst limit.
Discovery uses the game's minimap ping; stealth uses its raid-warning sound.

**Nearby stealth alerts only** requires a visible, attackable player within
10 yards, clear line of sight and a confirmed active stealth aura. Disabling
this option allows open-world warnings from received stealth events at any
distance. Battleground warnings always require nearby confirmation.

Enemy trinket cooldowns, resurrection estimates and victory projections depend
on observed events. Missing server telemetry can make them incomplete.

See the [user guide](docs/USER_GUIDE.md) for automation and customization details.

## License

[MIT License](LICENSE).
