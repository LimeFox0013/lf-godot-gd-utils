# LFRingMarkers3D

> A pool of flat rings on the ground, one per point you give it, all sharing one mesh and material.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_ring_markers_3d.gd` |
| **Tests** | `tests/test_lf_ring_markers_3d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils3D` (`flat_ring`, `translucent_material`) |

## When to use it

Use it to outline an area around several points at once: the no-build zone around each
tower while one is being placed, the reach of each unit. Call `display` each frame (or when
the points change) with the points; rings are made as needed and reused. For one ring that
follows a node, use `LFFollowRing3D`.

## Step by step

1. Choose *Scene → New Scene* and a **3D Scene**. Add a `Camera3D` at position `0, 8, 8` rotated `-45, 0, 0`.
2. Select the root, press *Attach Script*, and replace the script with:

   ```gdscript
   extends Node3D


   func _ready() -> void:
   	var markers := LFRingMarkers3D.new(3.0)   # radius 3
   	add_child(markers)
   	markers.display([Vector3(-4, 0, 0), Vector3(4, 0, 0)])
   ```
3. Press **F6** and save the scene. You should see two red rings on the ground.

## API

| Member | Signature | Description |
|---|---|---|
| `new` | `LFRingMarkers3D.new(radius, width, color, lift)` | Every argument is optional; `radius` is the outer radius, `width` the ring's thickness inward from it. Starts hidden. |
| `display` | `display(positions: Array) -> void` | One ring per position, lifted by `lift`; extra rings hide; shows the node. |
| `shown_count` | `shown_count() -> int` | How many rings are showing (0 while the node is hidden). |
| `DEFAULT_RADIUS`, `DEFAULT_WIDTH`, `DEFAULT_COLOR`, `DEFAULT_LIFT` | consts | `3.0`, `0.18`, a translucent red, `0.06`. |

## Usage

```gdscript
var zones := LFRingMarkers3D.new(5.0, 0.2, Color(0.2, 0.6, 1.0, 0.5))
add_child(zones)


func show_zones(towers: Array[Node3D]) -> void:
	var points := []
	for tower in towers:
		points.append(tower.global_position)
	zones.display(points)


func hide_zones() -> void:
	zones.visible = false
```

## Notes

- Rings are never freed: asking for fewer points hides the extras and asking for more later reuses them.
- Each ring is a flattened torus, not a filled disc: a translucent disc's caps z-fight into a spiky starburst.
- Positions are world points when the node sits at the origin; otherwise they are local to it.
