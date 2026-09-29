# AutoBG User Guide

Detailed configuration, interface controls, and gameplay reference for **AutoBG**.

---

## 1. Interface Controls & Movement

### Objective Timers (Arathi Basin & Alterac Valley)
- **Moving the Timers**: Drag the battleground header (e.g., "Arathi Basin") to reposition the timer cluster. The position is saved per character.
- **Chat Announcements**: Hold `Ctrl` and Left-Click any timer row (node, base, or respawn timer) to announce the remaining countdown to Battleground chat (`/bg`).
- **Countdown Appearance**: Under `/abg timers`, customize row width (180–420 px), height (18–32 px), UI scale (60–150%), and opacity (20–100%).

### Warsong Flag Carrier HUD
- **Targeting**: Left-click either the Alliance or Horde carrier card to target that player. If they are within range, AutoBG targets them directly; otherwise it attempts an exact name match.
- **Focus**: Right-click a carrier card to set that player as your focus target.
- **Mouseover Macros**: The carrier cards support mouseover casting; macro commands like `/cast [target=mouseover] ...` work over the cards.
- **Distance Display**: The distance is color-graded:
  - **Green**: $\le$ 30 yards
  - **Yellow**: 31–50 yards
  - **Orange**: 51–80 yards
  - **Red**: > 80 yards
  - **?**: Unknown or out of telemetry range

### Enemy Unit Frames (BattlegroundTargets)
- **Positioning**: Each bracket (10v10 WSG, 15v15 AB, 40v40 AV) saves its screen position independently. Drag the top header to move the list.
- **Custom Sizing**: Open `/bgt` or `/abg targets` to adjust row width, height, and font sizes separately for each bracket.
- **Targeting & Focus**: Left-click to target, right-click to set focus.
- **Trinket Cooldowns**: When an enemy's PvP trinket use is detected, a 180-second countdown icon appears on their row. Note that this is an estimate based on observed activations.

---

## 2. Open-World Spy Radar

AutoBG includes an open-world radar module that detects hostile enemy players and stealth activations.

### Stealth Alert Modes
In `/abg spy`, you can choose how stealth warnings behave:
- **Nearby stealth alerts only (Recommended & Default)**:
  Alerts only trigger when the hostile player is within 10 yards, with direct line of sight, and has an active stealth aura observed by the client. This prevents false alarms from combat-log noise far away.
- **Immediate Event Alerts (Nearby alerts disabled)**:
  Triggers a warning whenever a stealth cast or combat-log event reaches your client, regardless of range or line of sight.

### Radar Limitations
- AutoBG can only report actions and players that your game client actually receives from the server. It cannot see enemies that the server has not sent to your client.
- In battlegrounds, the Spy list automatically hides to reduce clutter, though stealth popups can still be enabled under `/abg targets`.

### Duel Testing Procedure
To verify that stealth alerts work properly with your client setup:
1. Challenge a friendly Rogue or Druid to a duel outside a battleground.
2. Open `/abg spy` and check whether **Nearby stealth alerts only** is enabled.
3. Have the opponent activate Stealth or Prowl at a distance:
   - With **Nearby stealth alerts only** enabled: The radar will list the player (if combat-log events are received), but will not sound an audio warning until the player moves within 10 yards with line of sight.
   - With **Nearby stealth alerts only** disabled: The audio and visual warning will trigger as soon as the stealth cast is observed.
4. Have the opponent break stealth and re-enter it to confirm subsequent alerts trigger reliably.

---

## 3. Automation Options

- **Auto-Queue**: Use `/abg q <bg>` or the multi-queue buttons in `/abg` to queue for specific or all battlegrounds.
- **Auto-Accept**: Enable under `/abg` or via `/abg a`. You can configure a delay (0 to 120 seconds) using `/abg delay <seconds>` to give yourself time to prepare. Auto-accept automatically pauses if your character is flagged AFK.
- **Auto-Leave**: Automatically leaves the match when the scoreboard appears at the end of the game (`/abg l`).
- **Auto-Rejoin**: Automatically rejoins the same battleground queue upon exiting a completed match (`/abg j`).
- **Smart Spirit Release**: Automatically releases your spirit upon death inside a battleground, while preserving active Soulstone or Reincarnation buffs (`/abg r`).
