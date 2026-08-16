# Not Enough Hands — House2

Godot 4 first-person horror prototype built around a four-level modular house.
`main.tscn` now uses `house2/house2.tscn`, assembled from the architecture and
furniture source packs under `assets/map`.

## Play

1. Open `project.godot` in Godot 4.7.
2. Run `main.tscn` with F6/F5.
3. Move with WASD, sprint with Shift, crouch with Ctrl, jump with Space, interact
   with E, blink with B, and release the mouse with Esc.

The player starts on the front path facing entrance 01. Every floor is physically
connected: cellar stairs lead into the garage, the main-hall stairs reach the
second-floor landing, and a second flight reaches the attic.

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

## Ghosts

The two ghosts are built to be opposites, so that learning one teaches you
nothing about surviving the other.

| | Statue (`ghosts/statue_ghost.gd`) | Crawler (`ghosts/crawler_ghost.gd`) |
|---|---|---|
| Senses | Sight — it freezes while any player can see it | Sound — it is blind, and hears movement |
| Counterplay | Keep looking at it; don't blink | Go quiet: crouch, or stop moving entirely |
| Space | Floors and stairs, on the navmesh | Floors, walls and ceilings; travels overhead |
| Arrival | Teleports into a scripted ambush, then vanishes | Announces itself with a fly-past, then sweeps the house |
| Kill | Grabs you during a blink or a look-away | Leaps 13 m at 21 m/s, or mauls what it touches |

The crawler hunts the last noise it *heard*, not where you are now. Sprinting,
landing a jump and working a door are loud; crouch-walking barely carries; and
standing still makes no sound at all, so its fix on you rots (`trail_decay`) and
it commits to a stale position. It leaves a trail of sound of its own — nails on
plaster as it moves, joints snapping every time it changes surface, breathing
once it is within a few metres.

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

Both ghosts report threat through `Player.set_threat_from`, which keeps the
horror overlay on whichever is currently worse.

## Verification

The smoke tests under `tests/` cover the four-level layout, all seven entrance
IDs, generated collision, basement-to-attic navigation, physical stair traversal,
statue stair chases and ambushes, crawler surface-crawling and noise hunting,
doors, interaction, and house audio.

Run one with:

```
godot --headless --script tests/crawler_ghost_smoke.gd
```
