# LFUtils2D

> Static Camera2D and 2D helpers: whether a camera can be read, the centre and world rect of what it shows this frame, switching a node between idle and physics processing like a camera, where a ray from a rect's centre meets its border, random points in a circle or around a rect, the spread of a set of points, sizing a sprite, reading a collision shape's size, a click mask from a texture's alpha and steering a body toward a direction.

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
`random_point_in_circle` drops loot around a spot; `random_point_outside_rect` picks a spawn
point just outside the screen (give it `camera_world_rect`); `max_pairwise_distance` tells how
far apart a group is (to zoom a camera out); `fit_sprite_to_size` and `shape_size` size a
sprite to a wanted size and read a collision shape's width and height.
`alpha_click_mask` / `apply_alpha_click_mask` make a `TextureButton` clickable only where its picture is not transparent, and `steer` accelerates a `CharacterBody2D` or `RigidBody2D` toward a direction.
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
| `random_point_in_circle` | `static random_point_in_circle(center: Vector2, radius: float, rng: RandomNumberGenerator = null) -> Vector2` | A point uniformly spread over the disc. Rolls from `rng` (an `LFRandom` works) when given, else Godot's global generator. |
| `random_point_outside_rect` | `static random_point_outside_rect(rect: Rect2, scale_range: Vector2 = DEFAULT_OUTSIDE_SCALE_RANGE, rng: RandomNumberGenerator = null) -> Vector2` | A point on the border of `rect` scaled about its centre by a factor from `scale_range` (x = min, y = max). One of the four sides with equal chance, then a point along it. Above 1 is outside the rect. |
| `max_pairwise_distance` | `static max_pairwise_distance(points: PackedVector2Array) -> float` | The largest distance between two points; 0.0 for fewer than two. Points with a NaN or infinite coordinate are ignored. |
| `fit_sprite_to_size` | `static fit_sprite_to_size(sprite: Sprite2D, size: Vector2) -> bool` | Sets `scale` so the shown texture area measures `size`; keeps the sign of each axis. False (and an error) for a null sprite or one without a texture. |
| `shape_size` | `static shape_size(shape_node: CollisionShape2D) -> Vector2` | The width and height of the shape's bounding box in its own units: a circle gives 2 x radius on both axes. `Vector2.ZERO` and an error without a shape. |
| `alpha_click_mask` | `static alpha_click_mask(texture: Texture2D, threshold := DEFAULT_ALPHA_THRESHOLD) -> BitMap` | A `BitMap` of the image's size, set where the pixel's alpha is above `threshold`. A compressed image is decompressed on a copy first; the texture is not changed. Null with an error for a null texture, one without an image, a NaN threshold or an image that cannot be decompressed. |
| `apply_alpha_click_mask` | `static apply_alpha_click_mask(button: TextureButton, threshold := DEFAULT_ALPHA_THRESHOLD) -> bool` | Sets `button.texture_click_mask` from its `texture_normal` so only visible pixels take clicks. False (with an error) for a null button or no texture; the button is left alone then. |
| `steer` | `static steer(body: Node2D, direction: Vector2, speed: float, delta: float, acceleration_ratio := DEFAULT_STEER_ACCELERATION_RATIO, force_gain := DEFAULT_STEER_FORCE_GAIN, slide := true) -> bool` | Accelerates a CharacterBody2D (its `velocity` moves toward `direction.normalized() * speed` by `speed * acceleration_ratio * delta`, then `move_and_slide()` unless `slide` is false) or a RigidBody2D (`apply_force((wanted - linear_velocity) * mass * force_gain)`; `delta` unused). Zero direction brakes; negative speed counts as 0. False with an error for another kind of node or a non-finite number. |
| `DEFAULT_ALPHA_THRESHOLD` | `const 0.1` | The default alpha threshold of `alpha_click_mask`. |
| `DEFAULT_STEER_ACCELERATION_RATIO` | `const 0.7` | Share of `speed` per second a CharacterBody2D gains in `steer`. |
| `DEFAULT_STEER_FORCE_GAIN` | `const 10.0` | Multiplier of the velocity gap times mass for a RigidBody2D in `steer`. |
| `DEFAULT_OUTSIDE_SCALE_RANGE` | `const Vector2(1.1, 1.4)` | The default `scale_range` of `random_point_outside_rect`. |

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
- `random_point_outside_rect` does not look at a camera: hand it the rect (for the screen, `LFUtils2D.camera_world_rect(camera)`). The point is on the scaled border, so with a rotated camera that rect is the bounding box and the point may be on screen at a corner.
- `alpha_click_mask` reads the texture's image, so the texture must be readable (an imported texture is, unless the project strips it); the mask has the image's pixel size. The mask is built once, so build it when the texture is set, not every frame.
- `steer` is for `_physics_process`: pass `delta` from it. Call it every frame the body should accelerate; it does not remember a direction. A CharacterBody2D keeps its velocity between calls, so multiply `body.velocity` by a drag factor yourself if you want friction. The two kinds of body do not feel the same: the character gains a fixed amount per second, the rigid body is pushed in proportion to the gap, so it eases in.
- `shape_size` returns the shape's own size: a `CollisionShape2D`'s `scale` and its parents' scales are not applied, and a shape offset from the node's origin still gives only its width and height.
- `fit_sprite_to_size` measures the visible area (`Sprite2D.get_rect()`), so a sprite sheet cut with `hframes`/`vframes` or `region_rect` is sized by one frame or the region, not the whole texture. It sets the sprite's own `scale`.
- `max_pairwise_distance` takes a `PackedVector2Array`; build one from positions with `PackedVector2Array(array_of_vector2)`.
- The camera functions accept a null or freed camera: they return the documented
  empty value and report no error. That is why their parameters are untyped (`Variant`):
  GDScript reports an error when a freed object is passed to a typed parameter, so a typed
  one could not take a freed camera. Anything else that is not a `Camera2D` (a live
  `Node2D`, a number) counts as no camera too, but is a mistake in the caller, so each
  function given it reports an error through `LFLogger`.
