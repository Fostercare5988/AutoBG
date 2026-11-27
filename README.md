# AutoBG [Fostercare5988]

Battlegrounds with less clicking and more knowledge, for OctoWoW (WoW 1.12.1).
The arena frames and the arena stealth tracker are their own addon,
[AutoArena](https://github.com/Fostercare5988/AutoArena).

## What it does

**Less clicking**

- **Queues** the battlegrounds you tick (Warsong Gulch, Arathi Basin, Alterac
  Valley) and an arena, with Mixed, Own faction or Any teams, at login or with
  one button.
- **A pop** rings, flashes the taskbar and says which one. A bar counts down the
  invite.
- **After the match** it can leave, queue the same one again and release your
  spirit. Deserter, AFK and death are respected.

**More knowledge**

- **Timers** for Arathi bases, Alterac towers, bunkers, graveyards and mines, the
  Warsong flag return, the game start and the spirit healer wave. Ctrl-click
  announces one.
- **Arathi Basin estimate:** win or loss, when, the final scores and the bases
  you need. The tick rates are learned from the matches you play.
- **Warsong Gulch carriers:** both carriers with the flag, health, assault stacks and
  distance. Click to target, right-click to focus.
- **Enemy frames** for 10, 15 and 40 players: health, cast bar, PvP trinket and
  racial cooldowns, distance and line of sight, stealth, death, raid mark, your
  target and focus, and how many of your group target each one. Left click
  targets, right click focuses.
- **Flag warnings** in Arathi Basin: an enemy opening a flag, or coming out of
  stealth at one.
- **Stealth warnings** when you see an enemy stealth, vanish, prowl or turn
  invisible within 40 yards, in sight: click the card to target him.
- **Spy list** in the open world: the enemy players around you, with level,
  class, health and distance.

Every frame keeps its own place in each battleground. A battleground where you
have not moved a frame uses the place it has outside.

## Commands

- `/abg` opens the settings (also under AddOn Options). *Preview frames* shows
  every frame so you can drag it into place.
- `/abg q` queues everything ticked; `/abg q wsg`, `ab`, `av` or `arena` queues one.
- `/abg leave` leaves your queues.
- `/abg efc` targets the enemy flag carrier.

## DLLs it calls

- **ClassicAPI** (required): GUID events, unit tokens by name, auras, casts,
  timers, secure-style unit buttons and the settings window.
- **NamPower** (required): `SPELL_GO_OTHER` and `BUFF_ADDED_OTHER` for the Spy
  list's far sightings.
- **UnitXP SP3** (optional): line of sight for the distances.

## Install

Unzip the release into `Interface\AddOns` so that
`Interface\AddOns\AutoBG\AutoBG.toc` exists, and restart the game.

Upgrading from 1.1.0 or older: delete the old `AutoBG` folder first. The addon
was written new, so its settings and frame places start fresh.
