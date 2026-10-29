# LFGroupCamera2D

> A Camera2D that keeps several nodes in view: it sits at their average position and zooms out as they spread apart.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene (it is a Camera2D) |
| **Files** | `lf_group_camera_2d.gd` |
| **Tests** | `tests/test_lf_group_camera_2d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils2D` |

## When to use it

Use it when one camera must follow more than one thing: two players in a co-op game, a
hero and its companions, a few units you want to watch. The camera centres on the middle
of the group and pulls back when the group spreads out, so nobody leaves the screen
(until they are further apart than the widest view allows). For a camera that follows one
thing, a plain `Camera2D` is enough; for a camera that follows a climb and never drops
quickly, see `LFRatchetFollow`; for a 3D strategy camera, `LFOrbitCamera`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*, pick *2D Scene* (a `Node2D` root).
2. Add two child `Node2D` nodes (*+ Add Child Node*, search "Node2D") and name them `A` and `B`. Give them different *Transform → Position* values, for example `0, 0` and `300, 0`.
3. Add a child node of type `LFGroupCamera2D` (*+ Add Child Node*, search "LFGroupCamera2D").
4. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node2D

   @onready var camera: LFGroupCamera2D = $LFGroupCamera2D


   func _ready() -> void:
   	camera.add_target($A)
   	camera.add_target($B)
   	camera.snap_to_targets()   # start on them instead of gliding in
   ```
5. Press *F6*. The camera sits between `A` and `B`. Change `B`'s position to `3000, 0`, press *F6* again, and the view starts zoomed out because the two are far apart.

## API

Everything the class offers; you only need the rows used above to get started. Zoom numbers are Godot's: a larger number is a closer view, so `min_zoom` is the widest view.

| Member | Signature | Description |
|---|---|---|
| `targets` | `var targets: Array` | The `Node2D`s to keep in view. Free ones are skipped. |
| `min_zoom` | `@export var min_zoom := 0.5` | The widest view: the zoom at `max_spread` or more. Below `MIN_ZOOM_FLOOR` (0.01) is read as that. |
| `max_zoom` | `@export var max_zoom := 1.0` | The closest view: the zoom at `min_spread` or less. At least `min_zoom` (a smaller value is raised to it). |
| `min_spread` | `@export var min_spread := 0.0` | Group spread up to which the view stays closest. 0 or less: half the viewport's shorter side. |
| `max_spread` | `@export var max_spread := 0.0` | Group spread from which the view is widest. 0 or less: 0.8 of the longer side of the world area the widest view shows. |
| `zoom_speed` | `@export var zoom_speed := 2.0` | How fast the zoom catches up per second; 0 or less freezes it. |
| `pixel_snap` | `@export var pixel_snap := false` | Rounds the camera position to whole pixels. |
| `add_target` | `add_target(target: Node2D) -> void` | Adds a node; ignores null, freed and duplicates. |
| `remove_target` | `remove_target(target: Node2D) -> void` | Removes a node. |
| `target_positions` | `target_positions() -> PackedVector2Array` | Global positions of the targets that exist and are in the tree; drops the others from `targets`. |
| `set_world_rect` | `set_world_rect(rect: Rect2, margin := 0.0) -> void` | Sets the four `limit_*` values to `rect` grown by `margin`, rounded outward. |
| `update_framing` | `update_framing(delta: float) -> void` | Moves to the middle of the targets and eases the zoom by `delta` seconds. Called every frame while `enabled`. Nothing happens with no targets. |
| `snap_to_targets` | `snap_to_targets() -> void` | Position and zoom at their goal at once. |
| `framing` | `static framing(positions: PackedVector2Array, zoom_range: Vector2, spread_range: Vector2) -> Dictionary` | `{center, zoom, spread}` for the positions (non-finite ones ignored); empty with none left. `zoom_range` is (widest, closest), `spread_range` is (closest until, widest from). |
| `smoothed_zoom` | `static smoothed_zoom(current, goal, speed, delta) -> float` | One frame-rate-independent step; `current` back for a `speed` or `delta` of 0 or less or a NaN. |
| `default_spreads` | `static default_spreads(viewport_size: Vector2, widest_zoom: float) -> Vector2` | The spreads used when `min_spread` / `max_spread` are 0, as (min, max). |
| `DEFAULT_MIN_ZOOM`, `DEFAULT_MAX_ZOOM`, `DEFAULT_ZOOM_SPEED`, `DEFAULT_MIN_SPREAD_FRACTION`, `DEFAULT_MAX_SPREAD_FRACTION`, `MIN_ZOOM_FLOOR` | `const float` | The defaults described above. |

## Usage

```gdscript
# A level script: two players, a map that is 6000 x 6000, and a camera that may show a
# little beyond the map's edge.
extends Node2D

@onready var camera: LFGroupCamera2D = $LFGroupCamera2D


func start_level(players: Array[Node2D]) -> void:
	for player in players:
		camera.add_target(player)
	camera.min_zoom = 0.6
	camera.set_world_rect(Rect2(0, 0, 6000, 6000), 300.0)
	camera.snap_to_targets()


# When a player is removed from the game, just free it: the camera skips it.
func player_died(player: Node2D) -> void:
	player.queue_free()
```

## Notes

- The zoom is set uniformly (`Vector2(z, z)`). It follows the spread, the distance between the two most distant targets, not their distance from the middle.
- The camera moves to the middle at once. For a softer follow turn on Godot's own `position_smoothing_enabled` on this camera.
- The zoom easing uses `1 - exp(-zoom_speed * delta)` of the gap each frame, so two frames of 8 ms and one of 16 ms ease the same amount.
- With `min_spread` or `max_spread` left at 0 the camera reads the viewport size when it frames; if the camera is not in the tree yet that size is taken as 0 and the derived spreads are 0, so call `snap_to_targets` or `update_framing` after it is in the tree.
- The camera works in `_process`. If the targets move in `_physics_process`, the camera may follow one frame late; call `update_framing` yourself from there if that matters.
