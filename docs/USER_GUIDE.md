# AutoBG guide

## Settings and movement

Open `/abg` and select General, Timers, Enemy frames or Spy.
Changes apply immediately. Close with the round close button or Escape;
closing also ends display previews.

**Preview frames** at the bottom of the window shows every AutoBG frame with
sample data: timers, flag carriers, enemy frames for the selected size, the Spy
list, and the stealth and flag warnings. It stays filled while the preview is
on; click it again or close the window to hide them.

Drag timer and enemy-list headers to move them. Carrier cards and both warnings
also support dragging. Settings and positions are shared across characters on
the account. Enemy frames store separate positions for 10-, 15- and 40-player
brackets. **Reset positions** moves every frame back to its default position
without resetting other choices.

## Queues and automation

Choose battlegrounds under General, then press **Queue now**.
**Leave queues** cancels outstanding queue work and existing queues.
The available battleground list comes from the server.

- **Accept queue pops:** enter when an invitation arrives. **Enter delay** waits
  0 to 78 seconds first; an invite runs out after about 80 seconds. If an
  invite ends before AutoBG enters, chat says so; lower the delay then. **Pause while AFK** stops accepting, queueing and
  rejoining while you are AFK.
- **Leave when it ends:** leave a completed match. Current or queued casts and
  terrain targeting are stopped before departure. Turning it off cancels a
  pending departure.
- **Queue again after leaving:** request the same battleground after a completed
  match. The request must match the returned battleground and then appear in
  queue status. Readiness and response retries are bounded. A manual queue or
  cancellation supersedes automatic work.
- **Release spirit:** release after dying in a battleground, while respecting
  a ready Soulstone or Reincarnation.
- **Queue on login:** request selected battlegrounds after login or UI
  reload. Deserter and dead/ghost checks still apply.

Queue sound (with **Play** to hear it), taskbar flashing and chat messages have
independent controls. These controls do not govern Spy alerts.

## Timers and flag carriers

The Timers page controls AB and AV captures, WSG flag respawns, gate opening,
queue waits, spirit-healer waves and AB victory estimates. Adjust countdown width,
height, scale and opacity there. Ctrl + left-click a timer announces its remaining
time to battleground chat.

Left-click a carrier card to target the player. Right-click focuses a currently
loaded, verified carrier. Carrier cards also support mouseover casting.
Distance colors indicate up to 30 yards, 31–50, 51–80 and over 80 yards; `?` means
distance is unavailable. Timers and projections remain estimates when the server
does not provide enough information.

## Enemy frames

Open `/abg targets` or `/bgt`. Pick 10v10, 15v15 or 40v40, then choose that size's
health text, realm suffix, stealth dimming and trinket. **Frame size** offers
Compact, Standard and Large; the **Custom size** sliders below set text size,
scale, width, height and opacity for anything in between. Text size runs 0 to 20,
from small but readable to large. Picking a size outside a battleground previews it so you can move it.

During a match the header shows how many enemies are alive. Drag it to move the
list out of combat; in combat it stays locked, so a stray click cannot move it.

**On each enemy** (shared by every size):

- **Cast bars:** each enemy's cast or channel appears beside its row with the spell
  icon and name. Orange is a cast, blue a channel, grey cannot be interrupted.
  Interrupts clear the bar at once. Only casts that start while the enemy is
  loaded near you can be seen. Left-click a cast bar to target the caster,
  right-click to focus them. **Cast bars on the left** picks the side; on the
  trinket's side the bar sits outside the trinket.
- **Mark enemies in range:** a thin green stripe on the left of each enemy
  within 80 yards, so the ones you can reach stand out. The header then adds how
  many are in range, in the same green. Nothing else changes; enemies you have
  not been near yet get no stripe.
- **Raid icons:** skull, cross and the other raid icons your group sets.
- **Who's on them:** an orange number beside the health shows how many of your
  group, you included, target that enemy.
- **Flag warnings:** in Arathi Basin and Alterac Valley, an enemy standing
  still at a flag their team does not hold gets a warning ("Opening
  Blacksmith"), a sound and a red OPENING on their row. It works even when they
  open straight out of stealth, which sends no cast bar. AutoBG learns where
  each flag is from the players who assault it, so it needs a game or two
  first; in Alterac Valley it learns from your own assaults. The warning has
  its own popup, apart from the stealth warning, so you can place each. Its
  icon is the Opening spell, learned the first time AutoBG sees one cast
  (a question mark until then). Ctrl + left-click the popup, or a row marked
  OPENING, to tell your battleground who is opening which flag. The trinket icon can sit on either side; its 180-second countdown
estimates cooldown from observed activations. Left-click targets; right-click
focuses a verified loaded player.

**Stealth warnings in BGs**, on the Spy tab, controls nearby confirmed warnings. Duplicate casts,
aura updates and immediate stealth re-entry do not restart warning sounds.
Different enemies share an eight-second warning limit; the same enemy has a
60-second stealth quiet period while retained in recent-contact history.
Enemy-row indicators still update while warnings
are suppressed.

## Open-world Spy

Open `/abg spy`. The list shows recent enemy names, levels and classes.
Hover for race, health, stealth state and observation age. New enemies enter at
the top; further activity updates their existing row. Up to 20 enemies are
tracked; **Enemies shown** controls the visible portion.
**Forget after** expires quiet rows. **Hide when empty** hides the
empty list. **Disable in raids** (on by default) turns the list and its alerts
off inside raids; `/abg spy raids` toggles it. **Clear list** clears observations without resetting recent alerts.

Each row shows the enemy's health as its bar and, while you can see them, the
distance in yards. **Shift-click** a name to put it on the kill-on-sight list:
the name turns red, and whenever that enemy shows up again AutoBG plays a raid
warning and says so in chat. **Ctrl-click** ignores an enemy for good; undo it
with `/abg spy ignore <name>`. `/abg spy kos` and `/abg spy ignore` list both
lists, and `/abg spy kos <name>` adds or removes a name by hand. AutoBG also
counts how often you meet each enemy and where you saw them last: hover a row,
or type `/abg spy stats` for the five you meet most. It keeps the latest 500.

**Alert sounds** controls all open-world warning sounds and defaults to off.
The list admits at most one alert per eight seconds. An enemy seen in the past
two minutes does not produce another discovery sound after row expiry, clearing
or eviction while retained in the separate 64-contact history. The same enemy's
stealth warnings stay quiet for 60 seconds while retained there. More than 64
distinct contacts can recycle the oldest history entry; the global eight-second
warning limit still applies.
Suppressed warnings are discarded.

**Stealth warnings** enables brief popups outside BGs. With **Only enemies I can
see** on, you must actually see the stealthed, attackable enemy, at any distance
your detection reaches, so detection gear and talents find them farther away.
Turn it off to warn on a received stealth event even when you cannot see the
enemy. Battleground warnings always need you to see them. Left-click a popup to
target the enemy, right-click to focus them.

The list contains client observations rather than a complete distance census.
It cannot reveal players or actions that the server has not sent to your client.

## Quick checks

Use **Preview frames** to check placement of every frame, including both
warnings, and the stealth warning sound (it plays when **Alert sounds** is on). For a gameplay check, have a duel opponent enter Stealth or Prowl at different
distances. With **Only enemies I can see** on, a warning needs a stealthed enemy
you can see.
Immediate re-entry should remain quiet; allow at least 60 seconds before testing
a fresh warning from that opponent.
