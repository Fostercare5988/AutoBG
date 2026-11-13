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
The available battleground list comes from the server. The button beside
Warsong Gulch and Arathi Basin picks the row each one joins: **Mixed**
(Cross-Faction, the default), **Own faction** (Factioned) or **Any** (First
Available); a row the server does not list falls back to First Available.
**Queue an arena** adds the arena picked under it (Skirmish, or a
rated 2v2, 3v3 or 5v5, which needs an arena team); `/abg q arena` queues it
alone. You can hold three queues at once and one of them an arena; choices
beyond that are reported and skipped. Release spirit never acts in an arena.

- **Accept queue pops:** enter when an invitation arrives. **Enter delay** waits
  0 to 78 seconds first; an invite runs out after about 80 seconds. AutoBG
  always enters a second before the invite runs out, also when a reload or a
  loading screen left it less time. If an invite still ends first, chat says so.
  Leaving the queue yourself is not reported. **Pause while AFK** stops accepting, queueing and
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

The Timers page controls AB and AV captures (AV mines count 5 minutes from the
moment they are taken), WSG flag respawns, gate opening,
queue waits, spirit-healer waves and AB victory estimates. Every timer is a bar
in its side's color (red Horde, blue Alliance) with a picture of what it
counts: each AB base its own, AV bunkers and towers a keep, graveyards a
headstone, mines a pick, WSG flags the banner. The time comes first ("21" under a
minute, "1:51" above, gold in the last seconds) and the name after it. Queue
bars fill toward the estimated wait. Adjust countdown width,
height, scale and opacity there. Ctrl + left-click a timer announces its remaining
time to battleground chat.

Teams on OctoWoW can mix factions, so AutoBG works out which side you play on
from the match itself: a member of your group carrying a flag or claiming a
base shows it. The enemy carrier (`/abg efc`, the flag on the enemy frames), the
Arathi Basin win estimate and the flag warnings follow that side.

Left-click a carrier card to target the player, right-click to focus them. With
a spell on the cursor, a left-click casts it on the carrier. Carrier cards also
support mouseover casting.
Distance colors indicate up to 30 yards, 31–50, 51–80 and over 80 yards; `?` means
distance is unavailable. Timers and projections remain estimates when the server
does not provide enough information.

## Enemy frames

Open `/abg targets` or `/bgt`. Pick 10v10, 15v15, 40v40 or Arena, then choose that size's
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
  loaded near you can be seen, and the game does not tell you when another
  player's cast is pushed back, so the bar keeps its first length. Left-click a cast bar to target the caster,
  right-click to focus them. **Cast bars on the left** picks the side; on the
  trinket's side the bar sits outside the trinket.
- **Mark enemies in range:** a thin green stripe on the left of each enemy
  within 80 yards, so the ones you can reach stand out. The header then adds how
  many are in range, in the same green. Nothing else changes; enemies you have
  not been near yet get no stripe.
- **Raid icons:** skull, cross and the other raid icons your group sets.
- **Who's on them:** an orange number beside the health shows how many of your
  group, you included, target that enemy.
- **Flag warnings:** in Arathi Basin only, an enemy you can see
  starting an Opening gets a warning ("Opening Blacksmith"), its own sound and
  a red OPENING on their row, with or without enemy frames. An opening started
  from stealth sends no cast, so an enemy who comes out of stealth at a flag
  their team does not hold and stands there warns too. AutoBG learns where
  each flag is from the players who assault it, so a flag it has not learned yet shows as "Opening a flag". The warning has
  its own popup, apart from the stealth warning, so you can place each. Its
  icon is the Opening spell, learned the first time AutoBG sees one cast
  (a question mark until then). Ctrl + left-click the popup, or a row marked
  OPENING, to tell your battleground who is opening which flag. The trinket icon can sit on either side; its 180-second countdown
estimates cooldown from observed activations. Left-click targets (or casts the
spell on your cursor at the enemy); right-click focuses. Hovering a row makes
the enemy your mouseover, for mouseover macros.

**Stealth warnings in BGs**, on the Spy tab, controls nearby confirmed warnings. Duplicate casts,
aura updates and immediate stealth re-entry do not restart warning sounds.
Different enemies share an eight-second warning limit; the same enemy has a
60-second stealth quiet period while retained in recent-contact history.
Enemy-row indicators still update while warnings
are suppressed.

## Arena

`/abg arena` opens the Arena tab. An arena never sends the enemy team, so everything
here is built from what the game shows of them. Every part has a switch.

- **Mana and energy bars:** a thin bar under each enemy row: mana, rage or energy.
- **Key abilities:** icons on the enemy row for Divine Shield, Blessing of Protection,
  Blessing of Freedom and Hammer of Justice, and nothing else. Grey border: the enemy used it,
  with the seconds since. Gold border: it is on that enemy right now (a blessing shows on whoever
  received it); once AutoBG has seen how long that rank lasts, the number counts down. The strip sits
  on the right of the row, past the cast bar if that is on the right.
- **Enemy pets:** pets and minions you have seen, under the enemy frames, with their
  owner and health. Click one to target it. Out of sight turns dim. Totems are left out.
- **Drinking alert:** a message and a sound when an enemy starts drinking.
- **Callouts to your team:** says in raid or party chat when an enemy drops to 25% health
  and when one dies, once each. Off until you turn it on.
- **Find enemies fast:** looks for enemies once a second, from what your team targets
  and, with UnitXP, by stepping through the nearby ones. It runs only while you have no
  target and clears it again; turn it off if the target flicker bothers you.
- **Shadow Sight timers:** the orbs appear 90 seconds into every round. A pickup shows
  15 seconds of sight for whoever took it, and that orb is back 3 minutes later. The bars
  sit with the other timer bars and move with Preview frames.

## Open-world Spy

Open `/abg spy`. The list shows recent enemy names, levels and classes. It
rests inside battlegrounds and arenas, where the enemy frames take over.
Hover for race, health, stealth state and observation age. New enemies enter at
the top; further activity updates their existing row. Up to 20 enemies are
tracked; when the list is full, a newcomer takes the place of an enemy you
have not seen for a while, never one still in view. While your mouse is over
the list it holds still, so a click hits the name you aimed at.
**Enemies shown** controls the visible portion.
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
