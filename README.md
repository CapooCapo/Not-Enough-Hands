# Not Enough Hands — House2

Godot 4 first-person horror prototype built around a four-level modular house.
`main.tscn` now uses `house2/house2.tscn`, assembled from the architecture and
furniture source packs under `assets/map`.

## Play

1. Open `project.godot` in Godot 4.7.
2. Run `main.tscn` with F6/F5.
3. Move with WASD, sprint with Shift, crouch with Ctrl, jump with Space, interact
   with E, blink with B, and press Alt to show or recapture the mouse.

The bottom-left **THỂ LỰC** bar is connected to the player's sprint reserve: it
drains while Shift-running and refills while walking or standing still.

Press **F1** to open the development panel. It can toggle invincibility and x3
movement speed, force the existing Statue, Crawler or Huntsman to manifest, and
select entrance 01-07 for an immediate real door attack. Opening the panel
releases the mouse automatically; F1 closes it and restores the previous mouse
mode. Forcing the Huntsman in puts it inside a house with no breach, which seals
it in — see below.

Interior bulbs occasionally sputter through a short, localised blackout. The
electrical snap and buzz is positional at the affected fixture, and the system
prefers a room near the player so the rare event is not wasted off-screen.

The player starts on the front path facing entrance 01. Every floor is physically
connected: cellar stairs lead into the garage, the main-hall stairs reach the
second-floor landing, and a second flight reaches the attic.

## Survive until dawn

The HUD clock starts at **11:55 PM**. Every 2.5 real seconds advances exactly
one in-game minute, including the midnight rollover. Reaching **6:00 AM** stops
the threats, pauses the world, and displays the dawn victory screen. The clock
is hidden while the door-ghost flashlight minigame owns the screen.

## House2 layout

- Basement: boiler and storage room; cellar exit 06 opens into a sunken exterior
  stairwell.
- Ground floor: kitchen, living room, dining room, garage, main hall, and storage.
  Entrances 01–03 are the front door, kitchen side door, and dining patio door.
- Second floor: two bedrooms, a large hall/stair landing, and bathroom. Entrances
  04 and 05 connect to separate exterior balconies.
- Attic: one full-footprint storage space beneath a pitched modular roof. Entrance
  07 opens onto a roof-entry deck.

Interior partitions use open modular frames so the navigation mesh, player, and
statue can circulate through every room. The seven exterior entrances remain
repairable defense doors used by the attack director.

## Door-ghost flashlight minigame

As soon as a door starts rustling, scratching, or being smashed, approach it,
aim at it, and press E to enter the 30-second flashlight minigame. Winning drives
the attacker away before it can do more damage. Timing out gives the attacker a
heavy hit and immediately starts a fresh attempt; repeated failures can still
break the door while the minigame is active.

A defense door that reaches zero durability can no longer be repaired
immediately, but the same E interaction and minigame remain available at the
breach. The world is covered in darkness and the mouse moves a small light:
hold it over the hidden face to build an invisible repel meter. Every fifteen
points the face jumps to another part of the screen and removes three points.
The balanced assist gives the flashlight a wider beam and face hit area. After
a 1.25-second grace period with no drain, missing it drains one point every 0.20
seconds. On first catching the face in the beam there is also a 6-16 percent
progress-scaled chance that it dodges immediately. Its side-to-side head shake,
distortion, twitch rate, audio pressure, and instant-dodge chance all intensify
toward 100 percent. Every relocation remains random among anchors away from the
current cursor position, so the face never deliberately appears near the light.

At an intact door, reaching 100 drives the attacker away; at a breached door it
unlocks physical repairs. A breached-door timeout triggers a jumpscare and
removes 20 points from the repair ceiling (down to a minimum of 10). The active
door cannot take normal damage outside these scripted failure hits. A development
safety switch also suspends statue and crawler attacks until 1.5 seconds after
the minigame closes.

## Ghosts

The three ghosts are built to be opposites, so that learning one teaches you
nothing about surviving the others.

| | Statue (`ghosts/statue_ghost.gd`) | Crawler (`ghosts/crawler_ghost.gd`) | Huntsman (`ghosts/hunter_ghost.gd`) |
|---|---|---|---|
| Senses | Sight — it freezes while any player can see it | Sound — it is blind, and hears movement | Tracks — it reads the marks you left on the floor |
| Counterplay | Keep looking at it; don't blink | Go quiet: crouch, or stop moving entirely | Keep off ground you have already walked; break its line at corners |
| Space | Floors and stairs, on the navmesh | Floors, walls and ceilings; travels overhead | Every room on every floor, on foot, room by room |
| Arrival | Teleports into a scripted ambush, then vanishes | Announces itself with a fly-past, then sweeps the house | Walks in through a door it has already broken |
| Presence | Gone the moment you look away | Gone between hunts | Never teleports, never vanishes while inside |
| Kill | Grabs you during a blink or a look-away; distant statues surge much farther per blink | Leaps 13 m at 21 m/s, or mauls what it touches | Charges faster than a sprint, then a half-second grab |

Standing still is the correct answer to the crawler, staring is the correct
answer to the statue, and neither does anything at all to the huntsman. That is
what it is for.

The crawler hunts the last noise it *heard*, not where you are now. Sprinting,
landing a jump and working a door are loud; crouch-walking barely carries; and
standing still makes no sound at all, so its fix on you rots (`trail_decay`) and
it commits to a stale position. It leaves a trail of sound of its own — nails on
plaster as it moves, joints snapping every time it changes surface, breathing
once it is within a few metres.

The main-house instance also has an authored containment volume. Outside noises
cannot lure it through an exterior opening, and any pounce or wall transition
that crosses the building limit is cancelled back to the previous valid frame.

### The crawler's hunt cycle

It is not a permanent threat. It runs an announced cycle out of its attic lair:

1. **Hidden.** Not in the house at all, for `hidden_delay_min`–`hidden_delay_max`
   seconds. Nothing can hurt you, and noise cannot summon it — a loud house only
   shortens the wait.
2. **Omen.** It appears and bolts across one player's field of view at
   `omen_speed`, far too fast to catch and unable to kill during the dash. This
   is the only warning, and a hunt never starts without it. If no player can be
   given a clean fly-past it screams from overhead instead.
3. **Patrol.** It sweeps a fixed route (`crawler_patrol_points` markers, in tree
   order) `patrol_laps` times, at `crawl_speed` — under half a walking pace,
   biased upward so it travels the walls and ceilings. It can crawl right over a
   player who is holding still, and will.
4. **Hunt.** A noise above `patrol_alert_loudness` breaks the sweep. This is the
   dangerous state: from up to `pounce_range` (13 m) it launches at
   `pounce_speed` (21 m/s), so making a noise anywhere near it is fatal. A
   missed pounce leaves it face down and helpless for `pounce_recovery` seconds;
   that window is the escape.
5. **Retreat.** Laps finished with nobody found: one scream, and it is gone.
   That scream is also the all-clear.

Route markers and the lair are level data, not code — drop `Marker3D`s into the
`crawler_patrol_points` and `crawler_lair` groups and the creature picks them up.
With no markers present it falls back to sweeping around wherever it was placed.

### The Huntsman — what comes in when a door finally breaks

The other two are summoned by the night. This one is summoned by failure: a
defense door that reaches zero durability is a hole, and `hunter_ghost.gd`
subscribes to every door's `breached` signal. `entry_delay_min`–`entry_delay_max`
seconds later it is standing outside that doorway, and then it walks in — on
foot, in view, no teleport. Rebuild the door inside that window and nothing ever
enters.

Once inside it stops in the doorway and sweeps the house with its lantern for
`entry_scan_duration` seconds. That is the announcement, and it is the only one.

**It hunts by track.** Every `spoor_interval` (0.4 s) each player writes a mark
to the floor: a position, a time, and a strength. Sprinting prints hard,
crouch-walking barely prints, and standing perfectly still still prints — faintly,
directly under your feet. Marks fade over `spoor_lifetime` (110 s) and become
unreadable below `cold_trail_strength`. The huntsman reads only what is inside
`nose_range` (7.5 m), takes the freshest mark it can find there, walks to it, and
reads again — and it only ever accepts marks *newer* than the last one it used,
so it walks your route forwards and can never be sent in a circle by your
history. Its knowledge is therefore local: rooms it has not physically reached
are genuinely safe, and the trail it is following is one you already left.

Outside a direct charge, every walking/tracking pace is multiplied by
`non_chase_speed_multiplier` (1.3), so its search movement is 30% faster than
the authored base speeds.

**Losing it and being found again.** With no readable mark it stops, sniffs and
turns on the spot (`cast_duration`). Then it lifts its head and takes the longest
scent it has — the freshest mark anywhere within `cast_lead_range` (30 m, most of
the house) — and walks to where that was. Against a player who keeps moving this
lead is always one address out of date and costs them nothing. Against a player
who has stopped, it is the thing that eventually opens their door. Only with
nothing readable anywhere does it fall back to quartering the house along the
`hunter_sweep_points` markers. A full sprint within `running_hearing_range` does
not make it hunt sound; it just gives it somewhere new to go and read the floor.

**Knowing when it is beaten.** Two separate tests, because wedging has two
shapes. The fast one watches the ground it actually covers, not the distance to
its destination — a route to the room above starts by walking *away* from it
toward the stairs, so distance-closed is a lie on a staircase. The slow one
(`no_closing_time`) watches whether it has closed any distance on its goal at
all over several seconds, which is what catches a body sliding back and forth
along a rail at full speed and getting nowhere. Fail either and it gives up on
that destination: it peels off at an angle
(`unstick_duration`), burns the mark, and writes off that patch of floor for
`give_up_memory` seconds so a motionless player printing fresh marks in an
unreachable spot cannot pin it there. Three failures in a row and, only while
nobody can see it, it relocates to the nearest room on its route. Without all of
this it was possible to leave it standing on a staircase for the rest of the
night, which is the one failure state a creature built on relentlessness cannot
have.

**The lantern is its eye.** It sweeps while it searches and locks dead-on when it
finds you, so a beam that stops moving is the worst thing you can see. Time in
the beam builds toward a lock (`spot_time_near`–`spot_time_far`, halved against a
crouched shape); inside `certain_range` it does not need the beam at all. A lock
means a horn and a charge at `charge_speed` (3.5 m/s against a 3.25 m/s sprint) —
a straight corridor is simply lost. What saves you is that it has `acceleration`
of a loaded truck and cannot move at full speed in a direction it is not already
facing (`off_axis_speed_floor`), so corners, doorways and stairs are the escape.
Break its line for `lose_sight_time` and it drops back to the trail — the trail
that is now hottest exactly where it lost you. And once it has had you in the
light it keeps your scent for the rest of the night (`marked_nose_bonus`), and
every lock extends its stay.

**The grab.** At `seize_range` it plants and reaches: `seize_windup` is half a
second, and that half second is the only window there is. The reach is
deliberately longer than a person's (2.35 m) because it is two and a half metres
of hunched shoulders with a hook on one arm — it takes people over the stairwell
bannister and through the gap in a doorway it cannot itself fit through. A
shorter reach left a player standing two metres away, lit, being stared at, and
completely untouchable.

**It does not give up on somebody it can see.** If it cannot close — pressed
against a rail with you on the other side — it drops navigation for
`direct_press_duration` and pushes straight at you instead, because pathfinding
is exactly what dithers along a railing. Only losing sight of you for
`lose_sight_time` (5 s) ends a lock.

**Bear traps.** While it is searching rather than charging, it periodically
stops to place a physical trap. At most three can exist in the house. Stepping
on one immobilizes that player for eight seconds; another player can interact
with the sprung trap and finish freeing them in two seconds.

**The sealed-house trap.** It leaves the way it came in, after `hunt_duration`, through any
door that is still a hole — and after `reentry_cooldown_min`–`reentry_cooldown_max`
seconds of quiet it lets itself back in through that same hole, so a breach left
standing keeps costing you all night. Rebuild every breach while it is inside and it has no
way out: it is sealed in with you until dawn (`sealed_inside`), it stops pacing
itself, and it gets faster and sharper-nosed. Repairing your own house is
therefore no longer an unambiguously correct move, which is the decision the
whole creature exists to force.

Route markers are level data, not code — drop `Marker3D`s into the
`hunter_sweep_points` group and it picks them up, and the average of those
markers is also what tells it which side of any doorway is indoors.

All three ghosts report threat through `Player.set_threat_from`, which keeps the
horror overlay on whichever is currently worse.

## Verification

The smoke tests under `tests/` cover the four-level layout, all seven entrance
IDs, generated collision, basement-to-attic navigation, physical stair traversal,
statue stair chases and ambushes, crawler surface-crawling and noise hunting,
doors, the breached-door minigame, temporary ghost safety, interaction, and
house audio. `dev_tools_smoke.gd` covers the F1 development controls, while
`night_clock_smoke.gd` verifies the 2.5-second minute tick,
midnight rollover, and the 6:00 AM victory boundary.

`hunter_ghost_smoke.gd` covers the huntsman's contract: it only gets in through a
breach, a door rebuilt before it arrives keeps it out entirely, it follows a
trail laid on the floor with no sight or sound to go on, a mark it can smell but
cannot reach does not freeze it, its lantern lock leads to a kill, attack safety
still blocks that kill, sealing the last breach traps it inside, and an open
breach lets it walk back out (and invites it back in).
`house_hunter_sweep_smoke.gd` then drops it into House2 itself, in three stages:
it must search real rooms across the baked navmesh instead of grinding into the
first wall; it must find a player standing perfectly still two floors above it;
and it must take a player who stands at the head of the stairs with the bannister
between them, which is the specific place it used to fail.

Run one with:

```
godot --headless --script tests/crawler_ghost_smoke.gd
```
