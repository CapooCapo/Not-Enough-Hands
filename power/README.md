# House electrical architecture

The two house maps share one electrical contract through node groups and stable
device IDs. Map-specific gameplay must not keep direct references to a
`PowerManager`.

## Responsibilities

- `PowerManager` owns total load and global/regional outages. Each house scene
  has exactly one manager in the `power_manager` group.
- `ElectricalDevice` owns configured consumption, requested on/off state, and
  forced-off reasons. Device scripts react to its `state_changed` signal.
- `LightSwitch` owns player interaction only. It resolves either a direct
  `controlled_device` NodePath or a stable `controlled_device_id`.
- `Interactable` remains the shared player-interaction contract. Electrical
  code does not duplicate raycast, prompt, range, or lock behavior.

## Generated house lights

Authored lights belong to `flickering_house_lights`. After a procedural house
finishes building, `PowerManager` gives every such light one runtime
`ElectricalDevice` child. The default load is configured by
`default_light_consumption`.

The stable device ID is the light node name without its final `Light` suffix:

| Light node | Device ID |
| --- | --- |
| `R_LIVINGLight` | `R_LIVING` |
| `R_KITCHENLight` | `R_KITCHEN` |
| `J1Light` | `J1` |

This convention lets procedural geometry be rebuilt without breaking switches.
Generated device IDs must be unique within one house.

## Persistent Villa fixtures

Manually positioned switches for the main Villa map are authored directly in
`villa_main.tscn`, outside `VillaHouse/Generated`:

```text
ElectricalFixtures/
  Floor_B1/
  Floor_00/
  Floor_01/
  Floor_02/
```

Set a switch's `controlled_device_id` to the room/junction ID it controls. Use
the direct `controlled_device` picker only for non-generated scenes or special
devices whose node path is intentionally stable.

Never place manual switches below `VillaHouse/Generated`; clearing or rebuilding
the procedural map deletes that subtree. `villa_house.tscn` remains responsible
only for the reusable procedural house structure.

## Adding another device type

Add an `ElectricalDevice` child, configure `device_id` and
`power_consumption`, then connect `state_changed` to the appliance's visual,
audio, or motor behavior. Registration, total-load updates, and blackout
behavior require no appliance-specific PowerManager code.
