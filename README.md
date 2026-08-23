# Not Enough Hands — House2

Godot 4 first-person horror prototype built around a four-level modular house.
`main.tscn` now uses `house2/house2.tscn`, assembled from the architecture and
furniture source packs under `assets/map`.

## Play

1. Open `project.godot` in Godot 4.7.
2. Run `main.tscn` with F6/F5.
3. Move with WASD, sprint with Shift, crouch with Ctrl, jump with Space, interact
   with E, blink with B, and press Alt to show or recapture the mouse.

The toilet minigame starts peeing automatically, building pressure for 0.75
seconds before it reaches full flow. Move the mouse to aim the stream and look
around at the same time; press **E** at any time to stop and leave the toilet.

The bottom-left **THỂ LỰC** bar is connected to the player's sprint reserve: it
drains while Shift-running and refills while walking or standing still.

Press **F1** to open the development panel. It can toggle invincibility, x3
movement speed, noclip flight, clear vision and the seven-entrance x-ray, force
the existing Statue, Crawler or Huntsman to manifest, and select entrance 01-07
for an immediate real door attack.

**Bay xuyên tường (noclip)** disables the player capsule and switches to free
flight: WASD follows where the camera is pointing, Space and Ctrl are straight
up and down, Shift is three times faster. Nothing collides while it is on, so
turning it off inside a wall leaves the player inside that wall.

**Soi 7 cửa xuyên tường** outlines every defense door through the house and tags
it with its entrance number and current range, so all seven can be found and
counted from anywhere without walking the ring. It reads the `defense_doors`
group, so it works on both maps.

**Sáng tối đa** takes the night off: no fog or volumetric fog, no vignette,
grain or threat distortion, no involuntary blinking (a ghost calling
`force_blink` is ignored), ambient light raised and a soft lamp on the camera.
The original `Environment` is kept and put straight back when the toggle is
cleared, so it never leaks into a real run.

Opening the panel
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

The HUD clock starts at **11:55 PM**. Every 1.5 real seconds advances exactly
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

## Second map — Biệt thự Vành Đai (`house3/`)

House2 is 18 × 12 m and its seven entrances are close enough that one player can
cover several of them. `NEH_map_spec_v2.md` asks for a house about four times
that size, where the geometry itself forces the team apart. That map lives in
`house3/` **beside** House2, not in place of it: `main.tscn` and every House2
test are untouched, and the villa reaches the player, the three ghosts, the
defense doors, the power system and the audio through exactly the same node
groups.

Run it with `house3/villa_main.tscn` (F6). House2 still runs from `main.tscn`.

| | House2 | Villa |
|---|---|---|
| Footprint | 18 × 12 m | 80 × 60 m, 40 × 30 cells of 2 m |
| Storeys | 4 at 3.0 m | 4 at 3.5 m (cellar, ground, first, attic) |
| Rooms | 12 | 33 plus a light shaft |
| Circulation | central hall | ring corridor + cross, 9 junctions per floor |
| Authoring | hand-placed in GDScript | generated from `neh_map_spec_v2.json` |

### How it is built

`house3/neh_map_spec_v2.json` holds the spec's §5–§9 tables verbatim and is the
only source of geometry. Per spec §10.2 nothing parses the ASCII plans in §3 —
they are for human readers, and their Vietnamese labels overwrite the cells they
sit on.

`villa_spec.gd` reads that file and rasterises one storey at a time following
§10.2: fill the footprint with wall, carve the rooms, carve the corridors, tag
the junctions, open the door cells, repaint the light shaft solid on the floor
above it, and cut the entrances into the outer wall. `villa_house.gd` then turns
that cell grid into geometry — greedy-rectangle floor slabs, wall runs merged
along each straight face, doorways, ramps, railings and lights — and publishes
room, junction, entrance, spawn and ghost-route markers.

Four compact 4 × 4 m WCs are cut into the outer room bands: two on the ground
floor and two upstairs, staggered between the north and south sides. Each is a
single-door dead end with one interactive toilet, one sink and one mirror. The
separate upstairs main bathroom is also reduced to 8 × 8 m and retains its
bathtub and shower.

### Editing generated villa parts

Open the scene the parts should live in - `house3/villa_main.tscn` is the one
that is played, and it is where the current bake sits - select its `VillaHouse`
node, and use the **Villa Authoring** controls in the Inspector:

1. Set detail, furniture and lighting to the version you want to edit.
2. Press **Bake Editable Parts**, then save the scene.
3. Expand `Generated/Level_*/Architecture`. Walls, floor slabs, ceilings and
   railings are now separate 2 m modules. Moving a body moves both its visual
   mesh and collider, while imported FBX and door scenes remain packed instances.

**Rebuild Preview** replaces `Generated` but keeps it disposable and unsaved.
**Clear Generated Parts** removes a baked version; save after clearing to return
to generation from `neh_map_spec_v2.json` at runtime. Baking deliberately switches
`Authoring Granularity` to `Editable Modules`. The default `Optimized` mode still
merges long wall and slab runs and should be used when no hand editing is needed.

Do not press either rebuild button after hand-adjusting baked parts unless those
changes can be discarded: rebuilding treats the JSON spec as authoritative.

The trade runs the other way too. `VillaHouse._ready()` returns as soon as a
baked `Generated` node exists, so a baked scene stops following
`villa_house.gd`: fix the builder and the saved parts keep the old geometry
until they are baked again. Re-bake after every builder or spec change, and run
`tests/villa_boot_smoke.gd`, which measures the baked stairs against the floors
they are supposed to join.

Two departures from the document, both deliberate:

- **The attic ladder (`V04`) is built as a steep companionway, not a ladder.** A
  `CharacterBody3D` cannot climb a vertical ladder in this project yet, so a map
  that shipped one would have an unreachable attic and an unreachable `E07`. It
  keeps its `hands_required: 2` and `cost: 5.0` metadata, so the two-handed rule
  from §11 can be enforced in gameplay code later without touching the geometry.
- **`E07` is laid flat.** The attic skylight has no wall to sit in, so its
  defense door is tipped onto its back and set into the attic ceiling as a
  boarded roof hatch. Standing it upright would have left a door slab in the
  middle of the attic floor and the skylight itself open to the sky.
- **`E05` gets a service culvert.** The spec puts the "outdoor" cellar door on
  the basement's west wall at column 19 — which is under the west wing, not
  outdoors. The coal chute therefore runs west as a covered culvert and surfaces
  in the garden. This preserves what §11 actually wants from `E05`: it stays the
  door that is 30–42 s from everything else.

One inconsistency in the spec is worth knowing about. §10.6 rule 5 forbids a room
with exactly one door, but the §5 door tables give exactly one to Thư viện,
Kho thực phẩm, Phòng trẻ em, Phòng tắm lớn and Phòng máy. The diagrams agree with
the tables, so the tables win and those rooms are listed in `single_door_rooms`
in the JSON. Any *new* one-door room still fails validation.

### Getting a ghost across the villa

Two things about the villa - neither of which House2 has - stopped every hunt
dead, and both look identical from the hallway: the statue manifests, walks a
few metres, then wanders off and never arrives.

**The staircases bake as islands.** Recast erodes every walkable surface by the
agent radius, and a 45-degree ramp is narrow enough that the erosion regularly
lifts a whole run clear of the floor it starts on. `V01`, the grand staircase in
the room the player spawns in, came out joined to the upper landing and to
nothing below it: a route from the foyer to the landing five metres overhead
went 152 m around the entire building. The statue only ever hunts a target on
its own storey, so it simply never used the stairs.

`villa_main.gd` therefore states each staircase as a chain of three
`NavigationLink3D`s - floor to the bottom step, bottom step to top step, top
step to the landing - rather than one span from storey to storey. Three hops
instead of one because **a link is not a teleport**: `NavigationAgent3D` hands
the far end over as the next path position and the body steers straight at it,
so every hop has to be walkable on its own. A single floor-to-landing span is
only walkable when it happens to lie along the run, and V01's does not - its
bottom step stops half a metre from the foyer's east wall, so its lower anchor
has to sit beside the staircase rather than in front of it. The middle hop
covers the other half of the problem: `V03` bakes with a metre-wide hole
halfway down the run, where the ground floor's slab edge clips its headroom.

None of the anchors are dead-reckoned. Each end is searched for - out along the
run, then to either side of it - and the first probe that lands on real
navigation at the right storey wins. The links can only be placed once the
NavigationServer has folded the region into its map and then re-iterated with
the links in it, so `villa_main` exposes `navigation_is_ready` and a
`navigation_ready` signal; a route asked for before that still walks around
every staircase in the house.

**Every internal doorway carries a closed door.** The navmesh is baked with the
door leaves deliberately lifted out - a closed door would otherwise freeze into
the route graph as a permanent wall and cut each storey into one island per
room - so ghost routes run straight through doorways. Nothing then opened them.
A ghost has no hands and never presses E, so the first door on its route held
the hunt for the rest of the night; a statue sent after a player two rooms away
would jam against a leaf and stand there. House2 has only open door frames,
which is why this never showed up there.

`door.gd` now lets anything in `hostile_ghosts` shoulder a leaf open, at the
cost of the swing, and swings it shut again five seconds after the doorway is
clear - leaving 48 doors standing open would quietly retire the "shut it behind
you" tactic. A hidden ghost clears its own collision mask, so asking whether the
leaf can block it is also asking whether it is really in the house yet: doors do
not open for something that has not manifested. `ghost_shoulder_enabled` turns
it off per door.

### Furniture

Rooms are not dressed by hand. `FURNITURE_PLANS` in `villa_house.gd` gives each
room *kind* four lists — `unique` pieces it has exactly one of, `large` carcass
furniture, `small` accents, and an optional `table`/`seat` centre group. The
builder walks the room's perimeter, collects every cell that has a wall on one
side and is not reserved, and stands pieces against those walls facing into the
room, one per four cells of floor. Bigger rooms also get a few pieces dropped on
a three-cell lattice in the middle, so a 24 m attic does not read as a furnished
corridor around an empty hall. Placement is seeded per room id, so a room looks
the same every launch and players can learn where the cover is.

Doorways, breach points and staircases — plus a one-cell margin around each —
are reserved before anything is placed. And because a room's geometric centre is
usually occupied by that room's own table, every room marker also publishes a
`clear_point` meta: the nearest tile something can actually stand on. Ghost
patrol routes, sweep points and the statue's start position all use it.

### Verifying the villa

```
godot --headless --script tests/villa_layout_smoke.gd
godot --headless --script tests/villa_seal_smoke.gd
godot --headless --script tests/villa_boot_smoke.gd
godot --headless --script tests/villa_editable_parts_smoke.gd
godot --headless --script tests/villa_ghost_chase_smoke.gd
```

`villa_layout_smoke.gd` runs spec §10.6 against the tables before any geometry
exists: flood-fill reachability from `SP_PLAYER_1` across all four storeys
including the vertical links, the light shaft being solid on `F_01`, every
entrance touching the room it claims, the junction graph being connected and
still containing a cycle (lose the cycle and the ring design is broken), and no
undeclared single-door room. It then builds the house in blockout detail and
checks the markers and groups it publishes.

`villa_seal_smoke.gd` fires rays out of all 1998 walkable cells — down, up, and
sideways at both waist and head height — and fails on any that escape through
something the spec did not ask for. The only openings it permits are the light
shaft, the stairwell holes and the attic skylight, and it derives all three from
the spec rather than from a hardcoded list.

`villa_boot_smoke.gd` boots `villa_main.tscn` at full detail and asks the baked
navmesh for real paths — hall to cellar, hall to attic, library to kitchen — plus
the seven defense doors at their correct storey heights, and that every one of
the 50-odd ghost route markers is reachable from the player spawn. That last
check is the guard against furnishing a room shut.

`villa_editable_parts_smoke.gd` builds the authoring variant, checks that walls,
floors and ceilings are cell-sized, then packs and reloads the result to prove
that generated nodes and gameplay groups survive baking.

`villa_ghost_chase_smoke.gd` covers the two hunt-killers above, because both are
invisible to a route query: it puts a player on V01's landing and the statue in
the foyer below and requires it to climb, then puts a player in the foyer and
the statue in the corridor behind it and requires it to come through the shut
door between them.

Between them these five caught every bug in this map worth recording: a
storey's worth of walls stacked at y=0, closed interior doors baking into the
navmesh as permanent walls, the basement stair running out of floor at its foot,
untiled floor strips in odd-height rooms, an unlined light shaft, unrailed
stairwell openings, and a wardrobe parked on the approach to the cellar stair.

`tests/villa_screenshot.gd` and `tests/villa_devshot.gd` are not tests — they
park a camera in the house (the second one with the dev toggles flipped) and
write PNGs to `user://villa_shots`. Two bugs got past every
assertion above and were only visible in those images: the kit staircase was
being scaled on the wrong axes, which made it twice its own length and half a
storey too tall, and the balustrades were placing one 1 m panel per 2 m cell,
leaving a metre of open air between every section. Both are now driven by
constants measured off the kit (`KIT_STAIR_RUN`, `KIT_STAIR_RISE`,
`KIT_RAIL_WIDTH`) instead of guessed factors.

The stair's 4.2 m full height includes a 1.2 m handrail above its 3 m landing;
it is not the tread rise. `villa_boot_smoke.gd` measures the tread mesh against
both connected floors so confusing those two dimensions cannot leave the upper
step floating below its landing again.

## Verification

The smoke tests under `tests/` cover the four-level layout, all seven entrance
IDs, generated collision, basement-to-attic navigation, physical stair traversal,
statue stair chases and ambushes, crawler surface-crawling and noise hunting,
doors, the breached-door minigame, temporary ghost safety, interaction, and
house audio. `dev_tools_smoke.gd` covers the F1 development controls, while
`night_clock_smoke.gd` verifies the 1.5-second minute tick,
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
