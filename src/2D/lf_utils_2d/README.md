# LFUtils2D

> Static Camera2D and screen-geometry helpers: whether a camera can be read, the centre and world rect of what it shows this frame, switching a node between idle and physics processing like a camera, and where a ray from a rect's centre meets its border.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_utils_2d.gd` |
| **Tests** | `tests/test_lf_utils_2d.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Any node that follows a `Camera2D` (a parallax layer, a scrolling background, a minimap
frame, a virtualized list) needs the same plumbing: a "can I read the camera yet?"
check, the centre of what the camera shows that already reflects a move made this
frame without double-stepping a smoothing camera, and a `process_callback` setting that
matches the camera's. These live here once. `rect_edge_point` pins something to the
border of a rect, such as an arrow at the screen edge pointing at an off-screen enemy.
To track a 3D target on the HUD, `LFTracker` already does the whole job; the scrolling
background and row-list cases are covered by `LFInfiniteScrollSprite` and
`LFVirtualGrid`.

## Step by step

Goal: print where a camera is looking, and where a ray from a rectangle's centre
leaves it.

1. *Scene → New Scene*, pick *2D Scene* (a `Node2D` root).
2. *+ Add Child Node*, search "Camera2D", *Create*. In the Inspector set
   *Transform → Position* to `500, 300`.
3. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node2D

   @onready var camera: Camera2D = $Camera2D   # the camera child we just added

   func _ready() -> void:
   	print("camera readable: ", LFUtils2D.camera_ready(camera))
   	# The world position at the middle of what the camera shows.
   	print("view centre: ", LFUtils2D.settled_view_center(camera))
   	# The whole visible area as a rectangle (position and size, in world units).
   	print("view rect: ", LFUtils2D.camera_world_rect(camera))
   	# A 200 x 100 rectangle; a ray from its centre pointing right leaves at (200, 50).
   	print(LFUtils2D.rect_edge_point(Rect2(0, 0, 200, 100), Vector2.RIGHT))
   	# Pointing down-right it leaves through the bottom edge at (150, 100).
   	print(LFUtils2D.rect_edge_point(Rect2(0, 0, 200, 100), Vector2(1, 1)))
   ```
4. Press *F6* and read the *Output* panel at the bottom.

You should see `camera readable: true`, a view centre of `(500, 300)` (the camera's
position), a view rect centred on it that is as large as your game window, then
`(200, 50)` and `(150, 100)`. The last two are the edge-pinning used for an arrow that
points at an off-screen enemy; the full script in Usage does exactly that.

## API

Everything the class offers; you only need the rows used above to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `camera_ready` | `static camera_ready(camera: Variant) -> bool` | True for a live Camera2D inside the tree, the only state its view can be read in. False for null, a freed camera, one outside the tree, or anything that is not a Camera2D; anything else that is not a Camera2D (a live Node2D, a number) is also reported as an error through `LFLogger`. |
| `settle` | `static settle(camera: Variant) -> void` | Brings an unsmoothed camera's view up to date with a transform change made this frame (`force_update_scroll`). Leaves a smoothing camera alone. No-op unless `camera_ready`. |
| `settled_view_center` | `static settled_view_center(camera: Variant) -> Vector2` | The world centre of what the camera shows this frame, after `settle`. `Vector2.ZERO` unless `camera_ready`. |
| `camera_world_rect` | `static camera_world_rect(camera: Variant) -> Rect2` | The camera's real view in world space: the bounding box of the viewport corners mapped through the viewport's canvas transform (zoom, offset, rotation). `Rect2()` unless `camera_ready`. |
| `apply_process_callback` | `static apply_process_callback(node: Variant, callback: Camera2D.Camera2DProcessCallback) -> void` | Turns on `_process` (idle) or `_physics_process` (physics) on `node` and turns the other off. Does nothing for a null or freed node; anything else that is not a Node is reported as an error through `LFLogger` and left alone. |
| `rect_edge_point` | `static rect_edge_point(rect: Rect2, direction: Vector2) -> Vector2` | Where the ray from `rect`'s centre along `direction` meets its border; the centre for a zero or non-finite direction. Only the direction's angle counts, not its length. |

## Usage

The full version: a script on a `Node2D` that stays on the centre of a camera's view (a vignette, a
weather effect) and an arrow that points at an off-screen target from the screen edge.

```gdscript
extends Node2D

@export var camera: Camera2D
@export var target: Node2D
@export var arrow: Sprite2D   # a child under a CanvasLayer, so it lives in screen space
# Idle or physics updates, like the camera's own setting.
@export var process_callback := Camera2D.CAMERA2D_PROCESS_IDLE:
	set(value):
		process_callback = value
		LFUtils2D.apply_process_callback(self, value)


func _ready() -> void:
	process_callback = process_callback   # apply the exported value once


func _process(_delta: float) -> void:
	_follow()


func _physics_process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if not LFUtils2D.camera_ready(camera):
		return   # no camera yet, or it is not in the tree
	global_position = LFUtils2D.settled_view_center(camera)

	# Is the target outside the camera's view? Pin the arrow to the screen edge.
	var view := LFUtils2D.camera_world_rect(camera)
	arrow.visible = target != null and not view.has_point(target.global_position)
	if arrow.visible:
		var direction := target.global_position - view.get_center()
		var screen := get_viewport_rect().grow(-32.0)   # keep 32 px from the border
		arrow.position = LFUtils2D.rect_edge_point(screen, direction)
		arrow.rotation = direction.angle()
```

## Notes

- Pass the viewport's **current** camera (`make_current()`, or the only enabled one). Godot computes the view only for that camera: `settled_view_center` and `camera_world_rect` on any other camera describe what the viewport shows (or the view from when it was last current), not that camera.
- `settle` matters only when you read the camera after it moved in the same frame (for example from a deferred call at the end of the frame). A smoothing camera has already stepped during its own processing; calling `force_update_scroll` on it again would advance the smoothing twice, so `settle` skips it.
- `camera_world_rect` is a bounding box: with a rotated camera it is larger than the visible area.
- `rect_edge_point` does not need a normalized `direction`: a short or long vector gives the same point. With a non-rotated camera, a
  world-space direction is also the screen-space direction, so the example above can
  use one for the other.
- The camera functions accept a null or freed camera: they return the documented
  empty value and report no error. That is why their parameters are untyped (`Variant`):
  GDScript reports an error when a freed object is passed to a typed parameter, so a typed
  one could not take a freed camera. Anything else that is not a `Camera2D` (a live
  `Node2D`, a number) counts as no camera too, but is a mistake in the caller, so each
  function given it reports an error through `LFLogger`.
