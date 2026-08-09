# Not Enough Hands — Graybox House

Godot 4 playable graybox of a four-level house. The scene contains environment,
geometry, collision, route labels, entrance lighting and a first-person test controller.

## View in Godot

1. Import/open `project.godot` with Godot 4.7.
2. Press **F6/F5** to run `main.tscn`.
3. Use **WASD** to move, mouse to look, **Space** to jump and **Esc** to release the mouse.
4. Follow the numbered, color-coded entrance markers and the east stairwell.

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
