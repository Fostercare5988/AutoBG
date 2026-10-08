# AutoBG guide

## Settings and movement

Open `/abg` and select General, Timers & FC, Enemy Frames or Spy.
Changes apply immediately. Close with the close button or Escape;
closing also ends display previews.

Drag timer and enemy-list headers to move them. Carrier cards and the Spy alert
also support dragging. Settings and positions are shared across characters on
the account. Enemy frames store separate positions for 10-, 15- and 40-player
brackets. **Reset Positions** resets positions without resetting other choices.

## Queues and automation

Choose battlegrounds under General, then press **Queue Selected**.
**Cancel All** cancels outstanding queue work and existing queues.
The available battleground list comes from the server.

- **Auto-Accept Queue Pop:** enter when an invitation arrives. Set a delay from
  0 to 119 seconds. **Pause Auto-Enter if AFK** prevents entering while AFK.
- **Auto-Leave BG on End:** leave a completed match. Current or queued casts and
  terrain targeting are stopped before departure. Turning it off cancels a
  pending departure.
- **Auto-Rejoin BG on Exit:** request the same battleground after a completed
  match. The request must match the returned battleground and then appear in
  queue status. Readiness and response retries are bounded. A manual queue or
  cancellation supersedes automatic work.
- **Auto-Release Spirit:** release after dying in a battleground, while respecting
  a ready Soulstone or Reincarnation.
- **Auto-Queue on Login:** request selected battlegrounds after login or UI
  reload. Deserter and dead/ghost checks still apply.

Queue sound, taskbar flashing and chat notifications have independent controls.
These controls do not govern Spy alerts.

## Timers and flag carriers

The Timers & FC page controls AB and AV captures, WSG flag respawns, gate opening,
queue waits, spirit-healer waves and AB victory estimates. Adjust countdown width,
height, scale and opacity there. Ctrl + left-click a timer announces its remaining
time to battleground chat.

Left-click a carrier card to target the player. Right-click focuses a currently
loaded, verified carrier. Carrier cards also support mouseover casting.
Distance colors indicate up to 30 yards, 31–50, 51–80 and over 80 yards; `?` means
distance is unavailable. Timers and projections remain estimates when the server
does not provide enough information.

## Enemy frames

Open `/abg targets` or `/bgt`. Select a bracket, then edit its width, height,
scale, font, health text, realm suffix and stealth dimming. Preview the bracket
before moving it. The trinket icon can sit on either side; its 180-second countdown
estimates cooldown from observed activations. Left-click targets; right-click
focuses a verified loaded player.

**Stealth alerts in BGs** controls nearby confirmed warnings. Duplicate casts,
aura updates and immediate stealth re-entry do not restart warning sounds.
Different enemies share an eight-second warning limit; the same enemy has a
60-second stealth quiet period while retained in recent-contact history.
Enemy-row indicators still update while warnings
are suppressed.

## Open-world Spy

Open `/abg spy`. The list shows recent enemy names, levels and classes.
Hover for race, health, stealth state and observation age. New enemies enter at
the top; further activity updates their existing row. Up to 20 enemies are
tracked; **Max Enemies Displayed** controls the visible portion.
**Inactivity Timeout** expires quiet rows. **Auto-Hide When Empty** hides the
empty list. **Clear List** clears observations without resetting recent alerts.

**Play enemy alerts** controls all open-world warning sounds and defaults to off.
The list admits at most one alert per eight seconds. An enemy seen in the past
two minutes does not produce another discovery sound after row expiry, clearing
or eviction while retained in the separate 64-contact history. The same enemy's
stealth warnings stay quiet for 60 seconds while retained there. More than 64
distinct contacts can recycle the oldest history entry; the global eight-second
warning limit still applies.
Suppressed warnings are discarded.

**Stealth alerts outside BGs** enables brief popups. With **Nearby stealth alerts
only** checked, the enemy must be visible, attackable, within 10 yards, in clear
line of sight and have a confirmed stealth aura. Uncheck it to warn on a received
stealth event even when the enemy is distant or unloaded. Battleground warnings
always use nearby confirmation.

The list contains client observations rather than a complete distance census.
It cannot reveal players or actions that the server has not sent to your client.

## Quick checks

Use **Test Spy**, **Test Detect** and **Test Stealth** to check placement and audio.
The two sound-test buttons intentionally play immediately.
For a gameplay check, have a duel opponent enter Stealth or Prowl at different
distances. Nearby mode should warn only after its range, sight and aura gates pass.
Immediate re-entry should remain quiet; allow at least 60 seconds before testing
a fresh warning from that opponent.
