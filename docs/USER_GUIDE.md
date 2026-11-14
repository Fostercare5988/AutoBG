# AutoBG guide

## Settings and moving frames

Type `/abg`, or open **Game Menu > AddOn Options > AutoBG**: the same five
pages (General, Timers, Enemy frames, Spy, Arena) are there, one column each.
Every change applies at once. Close the window with its close button or Escape.
Hover any switch for what it does in detail.

**Preview frames**, at the bottom of every page, shows every AutoBG frame with
samples: timers, flag carriers, the enemy frames of the size picked on the Enemy
frames page, the Spy list, and the stealth and flag warnings. Drag them where you
want them; click again or close the settings to hide them. **Reset positions**
puts every frame back in its first place and changes nothing else.

Drag a timer group or the enemy frames by their title; carrier cards and both
warnings drag anywhere. Settings and positions are shared by the characters of
an account. Each battleground size keeps its own enemy-frame place.

## Queues (General)

The General page follows a battleground from start to finish.

**Queue**: switch on what you want to play, then press **Queue now** (or type
`/abg q`). The button beside Warsong Gulch and Arathi Basin picks the teams:
**Mixed** (Cross-Faction, the default), **Own faction** (Factioned) or **Any**
(First Available); a row the server does not list falls back to Any. **Arena**
adds the arena type picked under it (Skirmish, or a rated 2v2, 3v3 or 5v5, which
needs an arena team). You can hold three queues, one of them an arena; what does
not fit is named in chat. **Queue on login** queues all of it when you log in or
reload. **Leave queues** leaves every queue. Nothing queues while you are AFK,
dead, or have Deserter; AutoBG says so and queues once you are alive again.

**When it pops**: **Enter automatically** enters when the invite comes, never
while you are AFK. **Enter after** waits up to 78 seconds first, and dims while
entering automatically is off. AutoBG always enters a second before the invite
runs out, also when a reload or a loading screen left it less time; if one still
runs out, chat says so. **Queue sound** (with **Play** to hear it) and **Flash the
taskbar** tell you when a queue pops or a match ends.

**After the match**: **Leave when it ends** leaves a finished match (casts and
spell targeting are stopped first). **Queue again after leaving** queues for the
same battleground or arena. **Release spirit** releases when you die in a
battleground, unless a Soulstone or Reincarnation is ready; never in an arena.

**Chat**: **Chat messages** tells you about queues, entering and leaving. What
stopped a queue (Deserter, every queue taken) always shows.

## Timers and flag carriers

The Timers page switches the countdowns: Arathi Basin bases, Alterac Valley
towers, graveyards and mines (a mine counts 5 minutes from the moment it is
taken), the Warsong flag return, the game start, the spirit healer wave and the
queues. Every timer is a bar in its side's color (red Horde, blue Alliance) with a
picture of what it counts: each Arathi base its own, Alterac bunkers and towers a
keep, graveyards a headstone, mines a pick, Warsong flags the banner. The time
comes first ("21" under a minute, "1:51" above, gold in the last seconds), then
the name. A queue bar fills toward the estimated wait; a queue that pops shows
how long its invite has left ("Warsong Gulch: enter"). Bar width, height, scale
and opacity are under **Look**. Ctrl + left-click a timer to announce it in
battleground chat.

In Arathi Basin a small panel beside the score estimates the end: win or loss
and when, the final scores, and how many bases you need (or must hold). It
learns what each number of bases earns on this server from the score as you
play, and starts with `~` while a count has not been seen yet. Ctrl + left-click
it to announce the estimate.

Teams on OctoWoW can mix factions, so AutoBG works out the side you play on from
the match: a member of your group carrying a flag or claiming a base shows it.
The enemy carrier (`/abg efc`, the flag on the enemy frames), the Arathi Basin
estimate and the flag warnings follow that side.

**Flag carrier frames** show both Warsong carriers with health, distance and
their assault stacks. Left-click a card to target the carrier, right-click to
focus; with a spell on the cursor a left-click casts it on them, and hovering
makes them your mouseover. Distance colors: up to 30 yards, 31-50, 51-80, over
80; `?` while the distance is not known.

## Enemy frames

Open `/abg targets` or `/bgt`. Pick the battleground size at the top (10v10,
15v15, 40v40 or Arena); outside a match this previews that size so you can place
it. Inside a match the page edits the size you are playing.

The left column is for that size alone: **Show the frames**, **Hide realm
names**, the **PvP trinket cooldown** (counted 3 minutes from a use you saw) and
which side it sits on. Its **size** has three presets, Compact, Standard and
Large, and sliders for text size, scale, width, height and opacity in between.

The right column, **Every size**:

- **Cast bars:** each enemy's cast or channel beside its row, with the spell icon
  and name. Orange is a cast, blue a channel, grey cannot be interrupted.
  Interrupts clear the bar at once. Only casts that start while the enemy is near
  you can be seen, and the game does not tell you when another player's cast is
  pushed back. Click a cast bar to target the caster. **Cast bars on the left**
  picks the side; on the trinket's side the bar sits outside the trinket.
- **Mark enemies in range:** a thin green stripe on each enemy within 80 yards;
  the title then says how many are in range, in the same green. Enemies you have
  not been near yet get none.
- **Who's on them:** an orange number beside the health: how many of your group,
  you included, target that enemy.
- **Flag warnings:** in Arathi Basin, an enemy you can see starting to open a
  flag gets a warning ("Opening Blacksmith") with its own sound and a red OPENING
  on their row. An opening started from stealth sends no cast, so an enemy who
  comes out of stealth at a flag their team does not hold and stands there warns
  too. AutoBG learns where each flag is from the players who assault it; until
  then it says "Opening a flag". Ctrl + left-click the warning, or a row marked
  OPENING, to tell your battleground.

Every row shows the enemy's health (or STEALTH, VANISH, PROWL and the like while
they are hidden, the row dimmed), and the raid icon your group put on them.
Left-click targets (or casts the spell on your cursor at the enemy), right-click
focuses, and hovering makes the enemy your mouseover. During a match the title
counts the living enemies; drag it out of combat (in combat it stays put). A dead
enemy's row counts down to the spirit healer's next wave ("DEAD 21"; `~` until
AutoBG has seen a wave), and turns alive at the wave unless their body still lies
in sight. Arenas have no wave, so there it just says DEAD.

## Arena

`/abg arena` opens the Arena page. An arena never sends the enemy team, so
everything here is built from what the game shows of them.

- **Mana and energy bars:** a thin bar under each enemy row: mana, rage or energy.
- **Key abilities:** icons for Divine Shield, Blessing of Protection, Blessing of
  Freedom and Hammer of Justice, and nothing else. Grey border: used, with the
  seconds since. Gold border: on that enemy right now (a blessing shows on whoever
  received it); once AutoBG has seen how long that rank lasts, it counts down.
- **Enemy pets:** pets and minions you have seen, under the enemy frames, with
  their owner and health. Click one to target it. Out of sight turns dim. Totems
  are left out.
- **Shadow Sight timers:** the orbs appear 90 seconds into every round. A pickup
  shows 15 seconds of sight for whoever took it, and that orb is back 3 minutes
  later. The bars sit with the other timers.
- **Drinking alert:** a message and a sound when an enemy starts drinking.
- **Callouts to your team:** says in your team's chat when an enemy drops to 25%
  health and when one dies, once each. Off until you turn it on.
- **Find enemies fast:** once a second, steps through the nearby enemies (with
  UnitXP) until the whole other team is listed, and only while you have no
  target, which it clears again. What your teammates target always counts.

## Open-world Spy

Open `/abg spy`. The list shows the enemy players around you: name, level,
class, their health as the bar and, while you can see them, the distance. It
rests in battlegrounds and arenas, where the enemy frames take over. A newcomer
enters at the top; up to 20 are kept, and a full list makes room only from
someone you have not seen for a while. While your mouse is over the list it holds
still, so a click hits the name you aimed at. Hover a row for race, health,
stealth and when you last saw them.

**Show the Spy list**, **Hide when empty** and **Off in raids** (on by default;
`/abg spy raids` too). **Forget after** takes quiet rows off the list,
**Enemies shown** is how many rows show, **Clear list** empties it.

Click a name to target, right-click to focus. **Shift-click** puts it on the
kill-on-sight list: the name turns red, and when that enemy shows up again AutoBG
plays a raid warning and says so in chat. **Ctrl-click** ignores an enemy for
good; `/abg spy ignore <name>` undoes it. `/abg spy kos` and `/abg spy ignore`
list both lists. `/abg spy stats` names the five enemies you meet most.

**Stealth warnings** show a short popup when you can see an enemy in stealth
outside battlegrounds, at any distance your detection reaches. **Warning sounds**
adds a sound to it and to a new enemy (off by default). **Stealth warnings in
battlegrounds** does the same in battlegrounds, with a sound. Warnings share an
eight-second limit, and the same enemy stays quiet for 60 seconds; a warning held
back is dropped, not played later. Left-click a popup to target the enemy,
right-click to focus them.

The list is what your client has seen, not a count of everyone within a
distance: the game sends nothing about players or actions out of your reach.

## Quick checks

**Preview frames** shows every frame and both warnings, with the stealth sound
when **Warning sounds** is on. For a real check, have a duel opponent enter
Stealth or Prowl where you can see them; wait 60 seconds before testing them
again.
