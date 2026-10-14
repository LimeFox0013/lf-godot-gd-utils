# LFFollowRing3D

> A pulsing ring on the ground that follows a 3D node and hides when there is nothing to follow: a selection marker.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_follow_ring_3d.gd` |
| **Tests** | `tests/test_lf_follow_ring_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils3D` (`flat_ring`, `translucent_material`) |

## When to use it

Use it to show which unit, building or pickup is selected, right on the field. Set `target`
and the ring appears under it and pulses; clear it and the ring hides. For rings at many
fixed points use `LFRingMarkers3D`.

## Step by step

1. Choose *Scene → New Scene* and a **3D Scene**. Add a `MeshInstance3D` child named `Box` and give it a *Mesh* of *New BoxMesh*; add a `Camera3D` at position `0, 4, 4` rotated `-45, 0, 0`.
2. Select the root, press *Attach Script*, and replace the script with:

   ```gdscript
   extends Node3D


   func _ready() -> void:
   	var ring := LFFollowRing3D.new()   # the default look
   	add_child(ring)
   	ring.target = $Box                 # the ring appears under the box
   ```
3. Press **F6** and save the scene. You should see a pale ring pulsing on the ground around the box.

## API

| Member | Signature | Description |
|---|---|---|
| `new` | `LFFollowRing3D.new(inner_radius, outer_radius, color, initial_pulse_speed, initial_pulse_amount, initial_lift)` | Every argument is optional; the ring's shape and colour are fixed here. Starts hidden. |
| `target` | `var target: Node3D` | The node to follow; null, freed or outside the tree hides the ring. |
| `pulse_speed` | `var pulse_speed := DEFAULT_PULSE_SPEED` | Radians per second. |
| `pulse_amount` | `var pulse_amount := DEFAULT_PULSE_AMOUNT` | The scale swings this far either side of 1. |
| `lift` | `var lift := DEFAULT_LIFT` | Height above the target, in world units. |
| `DEFAULT_INNER_RADIUS`, `DEFAULT_OUTER_RADIUS`, `DEFAULT_COLOR`, `DEFAULT_PULSE_SPEED`, `DEFAULT_PULSE_AMOUNT`, `DEFAULT_LIFT` | consts | `1.1`, `1.3`, a pale `Color(0.95, 0.91, 0.86, 0.85)`, `3.0`, `0.06`, `0.05`. |

## Usage

```gdscript
# A gold ring, wider and slower, following whatever is selected.
var ring := LFFollowRing3D.new(1.6, 1.9, Color(1.0, 0.8, 0.2, 0.8), 2.0, 0.1)
add_child(ring)


func select(unit: Node3D) -> void:
	ring.target = unit   # pass null to hide it
```

## Notes

- The ring only processes while it is visible, so a hidden ring costs nothing per frame.
- It follows the target's position every frame; it does not copy its rotation or scale.
- It is a flat torus drawn on one side, so it is seen from above only.
