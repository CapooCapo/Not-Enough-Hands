# Not Enough Hands — Graybox House

Godot 4 playable graybox of a four-level house. The scene contains environment,
geometry, collision, route labels, entrance lighting and a first-person test controller.
The plan uses an approximately 28 x 19.6 metre footprint. Room zoning follows
the supplied haunted-house specification: foyer/living/dining/library/kitchen on
the ground floor and residential rooms upstairs; the attic is now a roomless maze.
An offset entrance foyer and alternating enclosed stair lobbies break direct
sightlines, creating room-to-corridor-to-landing transitions for chase pacing.
Each level has a different topology: a basement service loop, asymmetric ground
floor wings, an upper ring corridor, and a roomless open attic maze.

## View in Godot

1. Import/open `project.godot` with Godot 4.7.
2. Press **F6/F5** to run `main.tscn`.
3. Use **WASD** to move, mouse to look, **Space** to jump and **Esc** to release the mouse.
4. Follow the numbered, color-coded entrance markers and the east stairwell.

The test player starts outside the front entrance, facing the house. A flat
80 x 80 metre ground plane surrounds the house at ground-floor height, placing
the basement fully underground. A lower hidden foundation prevents map falls.

## Layout

- Basement: storage loop, main stair hall, purple cellar entrance.
- Ground floor: foyer and utility/side rooms; green front door, orange back
  door, and cyan side window.
- Upper floor: landing and bedroom loop; pink balcony door and yellow window.
- Attic: open circulation space; red attic hatch/catwalk entrance.
- Three broad staircases with real steps form the internal route through all four levels.
- A pitched two-slab roof encloses the attic and gives the graybox a believable
  residential silhouette.

Every infiltration point uses a unique color, silhouette/size, light, and a
world-space label describing the room or route it enters.

## Acceptance check

1. Inspect the U-shaped stairs from basement through ground and upper floor to
   the attic.
2. Verify all seven numbered markers are visually distinct and open into a
   room or circulation route.
3. Walk through `main.tscn`; the included controller is intentionally minimal and
   exists only to verify traversal and collision.
