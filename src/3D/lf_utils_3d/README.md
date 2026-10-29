# LFUtils3D

> Static 3D helpers: project a world position to the screen and pick from the screen (physics ray, plane, segment), ground-marker meshes, point-set distances and best-of-N sampling, and geometry on the XZ plane — points on a circle, uniform random points in a disk, random and away-from directions, flattening and planar distance.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_utils_3d.gd` |
| **Tests** | `tests/test_lf_utils_3d.gd`, `tests/test_lf_xz_geometry.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Reach for it whenever 3D gameplay meets the screen or the ground: putting a health bar
over an enemy's head (`world_to_canvas_position`), finding the unit or ground point under
the mouse (`raycast_from_screen`, `screen_to_plane`), drawing a range ring under a tower
(`flat_ring` + `translucent_material`), dropping loot at a random spot around a chest
(`random_point_in_circle_xz`), knocking a unit away from an explosion (`away_xz`), or
picking the spawn point farthest from every player (`farthest_sample_xz`). The `_xz`
helpers work on the flat ground and ignore height.

To keep a HUD marker on a 3D target, including at the screen edge when it is off
screen, use `LFTracker`, which builds on these functions. For 2D camera helpers see
`LFUtils2D`.

## Step by step

Goal: a name label that follows a moving cube, drawn at the cube's screen position.
(`world_to_canvas_position` turns a point in the 3D world into a pixel position.)

1. *Scene → New Scene*, pick *3D Scene* (a `Node3D` root).
2. Add three children with *+ Add Child Node*:
   - `Camera3D`: in the Inspector set *Transform → Position* to `0, 3, 8`.
   - `MeshInstance3D`, renamed `Cube` (select it, press F2): set *Mesh* to
     *New BoxMesh* (click the empty Mesh slot).
   - `Label`, with *Text* set to `Cube`.
   The Label appears under the 3D root; it is drawn on top of the 3D view.
3. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node3D

   @onready var camera: Camera3D = $Camera3D
   @onready var cube: MeshInstance3D = $Cube
   @onready var label: Label = $Label

   func _ready() -> void:
   	# Distance on the flat ground (x and z), ignoring height: 5 up, then 3 and 4 across.
   	print(LFUtils3D.distance_xz(Vector3(0, 5, 0), Vector3(3, 0, 4)))   # prints 5.0

   func _process(_delta: float) -> void:
   	# Swing the cube left and right, 2 world units each way.
   	cube.position.x = sin(Time.get_ticks_msec() / 1000.0) * 2.0
   	# Where the point just above the cube appears on screen, in pixels.
   	# "Variant" means the answer can be a position or null (point behind the camera).
   	var screen: Variant = LFUtils3D.world_to_canvas_position(camera, cube.global_position + Vector3(0, 1, 0))
   	label.visible = screen != null
   	if screen != null:
   		label.position = screen
   ```
4. Save the scene and press *F6*. Check the *Output* panel.

You should see the cube sway with the "Cube" label following just above it, and `5.0`
in the Output panel. The `_xz` functions (`distance_xz`, `random_point_in_circle_xz`, ...)
all work on the flat ground and ignore height. The mouse-picking functions are in Usage.

## API

Everything the class offers; you only need the rows used above to get started.

### Constants

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_EPSILON` | `const float = 0.001` | Default `epsilon` of `away_xz`, in world units. |
| `DEFAULT_RAY_LENGTH` | `const float = 1000.0` | Default `length` of `raycast_from_screen`, in world units. |
| `DEFAULT_RING_FLATTEN` | `const float = 0.1` | Default `flatten` of `flat_ring`: the ring's height as a fraction of the torus's. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `camera_ready` | `static camera_ready(camera: Variant) -> bool` | True for a live Camera3D inside the tree; false for null, a freed camera, one outside the tree, or anything that is not a Camera3D. The camera parameters below are untyped so a freed camera can be passed without a script error; each answers "no camera" unless this is true. Anything else that is not a Camera3D (a live Node3D, a number) is also reported as an error through `LFLogger`; null and a freed camera are not. |
| `world_to_canvas_position` | `static world_to_canvas_position(camera: Variant, world_position: Vector3) -> Variant` | The screen position (viewport pixels) of `world_position`, or null unless `camera_ready(camera)` or when the point is behind it. |
| `ids_in_screen_rect` | `static ids_in_screen_rect(camera_or_project: Variant, a: Vector2, b: Vector2, positions: Dictionary) -> Array` | The keys of `positions` (key to world position) that appear inside the screen rectangle `a`-`b` (left and top edges count, right and bottom do not), in `positions` order; for a drag-select box. Takes a camera or a projection Callable. |
| `raycast_from_screen` | `static raycast_from_screen(camera: Variant, screen_pos: Vector2, mask: int, length := DEFAULT_RAY_LENGTH) -> Dictionary` (1000.0) | The first physics hit on the `mask` layers along the view ray under `screen_pos` (the `intersect_ray` dictionary: `position`, `normal`, `collider`, …); empty on a miss or unless `camera_ready(camera)`. |
| `screen_to_plane` | `static screen_to_plane(camera: Variant, screen_pos: Vector2, plane: Plane) -> Variant` | Where the view ray under `screen_pos` meets `plane` (Vector3); null on a miss or unless `camera_ready(camera)`. |
| `screen_distance_to_segment` | `static screen_distance_to_segment(camera: Variant, screen_pos: Vector2, a: Vector3, b: Vector3) -> float` | Pixels from `screen_pos` to the on-screen projection of segment `a`–`b`; INF when either end is behind the camera or unless `camera_ready(camera)`. |
| `screen_direction` | `static screen_direction(camera: Variant, world_position: Vector3) -> Vector2` | Unit screen direction (y down) from the centre toward the point, read in camera space, so it is the true side in front, beside or behind the camera. `Vector2.DOWN` when the point is on the camera's view axis (straight ahead, straight behind, or at the camera), or unless `camera_ready(camera)`. |
| `translucent_material` | `static translucent_material(color: Color, cull := BaseMaterial3D.CULL_DISABLED) -> StandardMaterial3D` | Unlit, alpha-blended material in `color`, two-sided by default — for ground markers and previews. |
| `flat_ring` | `static flat_ring(inner: float, outer: float, material: Material, flatten := DEFAULT_RING_FLATTEN) -> MeshInstance3D` (0.1) | A thin ring on the XZ plane: a `TorusMesh` squashed to `flatten` of its height, with `material` as override. |
| `nearest_distance` | `static nearest_distance(point: Vector3, points: Array[Vector3]) -> float` | 3D distance from `point` to the nearest of `points`; INF when empty. |
| `farthest_sample_xz` | `static farthest_sample_xz(half_extent: float, samples: int, away_from: Array[Vector3], accept: Callable = Callable(), rng: RandomNumberGenerator = null) -> Variant` | Of `samples` uniform points in the XZ square ±`half_extent` (Y 0), the one `accept(point) -> bool` takes that is farthest from its nearest `away_from` point; null when none is accepted. Rolls x then z from `rng` when given. |
| `to_xz` | `static to_xz(v: Vector3) -> Vector2` | `Vector2(v.x, v.z)`. |
| `distance_xz` | `static distance_xz(a: Vector3, b: Vector3) -> float` | Distance on the XZ plane, height ignored. |
| `random_point_in_circle_xz` | `static random_point_in_circle_xz(center: Vector3, radius: float, rng: RandomNumberGenerator = null) -> Vector3` | Uniform-by-area random point within `radius` (≥ 0) of `center` on the XZ plane (sqrt-scaled distance), from `rng` when given, else the global generator; Y equals `center.y`. |
| `point_on_circle_xz` | `static point_on_circle_xz(center: Vector3, radius: float, angle: float) -> Vector3` | The point at `angle` (radians, +X toward +Z) on the XZ circle around `center`; Y equals `center.y`. |
| `random_direction_xz` | `static random_direction_xz(rng: RandomNumberGenerator = null) -> Vector3` | A uniformly random unit XZ direction, by angle (from `rng` when given, else the global generator) — never zero, never biased toward the diagonals. |
| `away_xz` | `static away_xz(from: Vector3, origin: Vector3, epsilon := DEFAULT_EPSILON, rng: RandomNumberGenerator = null) -> Vector3` (0.001) | Unit XZ direction from `origin` to `from` (height ignored); a random one when they are within `epsilon` on XZ. |

## Usage

Mouse picking and random placement. A script on the root `Node3D` of a level with a `Camera3D` child named `Camera3D`. It
shows a range ring that follows the ground point under the mouse, and on click drops a
marker at a random spot near it.

```gdscript
extends Node3D

const UNIT_LAYER := 2   # collision layer 2 as a bitmask (layer 1 = 1, layer 2 = 2, layer 3 = 4)

@onready var camera: Camera3D = $Camera3D
var ring: MeshInstance3D
var rng := RandomNumberGenerator.new()   # or an LFRandom with a seed, to replay rolls


func _ready() -> void:
	ring = LFUtils3D.flat_ring(1.8, 2.0, LFUtils3D.translucent_material(Color(0.2, 0.8, 1.0, 0.5)))
	add_child(ring)


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var ground: Variant = LFUtils3D.screen_to_plane(camera, mouse, Plane(Vector3.UP, 0.0))
	ring.visible = ground != null   # null when the mouse ray misses the ground
	if ground != null:
		ring.global_position = ground


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := LFUtils3D.raycast_from_screen(camera, event.position, UNIT_LAYER)
		if not hit.is_empty():
			print("clicked ", hit.collider.name)
			return
		var ground: Variant = LFUtils3D.screen_to_plane(camera, event.position, Plane(Vector3.UP, 0.0))
		if ground != null:
			var marker := MeshInstance3D.new()
			marker.mesh = SphereMesh.new()
			add_child(marker)
			marker.global_position = LFUtils3D.random_point_in_circle_xz(ground, 1.5, rng)
			# Where the marker appears on screen (null if it is behind the camera):
			var on_screen: Variant = LFUtils3D.world_to_canvas_position(camera, marker.global_position)
			print("marker at screen ", on_screen)
```

## Notes

- `world_to_canvas_position` answers null for a point behind the camera and for a camera that is null, freed or not in the tree (no engine or script error). To place an off-screen indicator, use `LFTracker`, or `screen_direction` with `LFUtils2D.rect_edge_point`.
- `raycast_from_screen` queries the physics space directly, so a body added this frame is found only after the next physics frame.
- `flat_ring` squashes a torus rather than drawing a disc: a translucent disc's top and bottom caps z-fight into a starburst. Rings of one size can share one mesh: create one with `flat_ring` and assign its `mesh` to the others.
- `farthest_sample_xz` is best-of-N max-min sampling (a spawn point, a safe spot, an AI placement): more samples get closer to the true farthest point. With `away_from` empty it returns the first accepted sample.
- The random helpers (`random_point_in_circle_xz`, `random_direction_xz`, `away_xz`) roll from the `rng` you pass (a seeded game's own generator) and fall back to the global generator (`randf`) without one.
- Pass an `LFRandom` (or any `RandomNumberGenerator`) to make them replayable.
