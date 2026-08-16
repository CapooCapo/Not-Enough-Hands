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

## Verification

The smoke tests under `tests/` cover the four-level layout, all seven entrance
IDs, generated collision, basement-to-attic navigation, physical stair traversal,
statue stair chases and ambushes, doors, interaction, and house audio.
