# LFInfiniteScrollSprite, LFBackgroundController

> A repeating-texture `Sprite2D` layer that scrolls its texture region with camera movement (and optionally drifts on its own), plus a controller that forwards one camera delta per frame to many such layers and keeps them on the camera's view.

| | |
|---|---|
| **Files** | `lf_infinite_scroll_sprite.gd`, `lf_infinite_scroll_sprite.tscn`, `lf_background_controller.gd`, `lf_background_controller.tscn` |
| **Tests** | `tests/test_lf_infinite_scroll_sprite.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils2D` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFInfiniteScrollSprite` | Node: add it to a scene |
| `LFBackgroundController` | Node: add it to a scene |

## When to use it

Use it for a background that never ends: a starfield behind a space shooter, sky and
hills that slide past slower than the ground in a side-scroller, or clouds drifting
behind a main menu. Each layer is one sprite with a repeating texture; give it a
`position_factor` below 1 to make it look far away. For several layers that move
together, let one `LFBackgroundController` drive them all from the camera.

Godot's built-in `Parallax2D` is the simpler choice when the background just follows the
camera of the viewport it is drawn in. Use these nodes when the scroll comes from
elsewhere: they take an explicit world-space movement (`apply_camera_delta`), so a
`Camera2D`, a 3D camera's motion projected to 2D, a scripted speed or a menu can drive
them. A layer is one region-shifted sprite with no tile copies, and one controller fans
a single movement out to any number of layers.

## Step by step

Goal: a starfield that slides past as a camera moves. You need a seamless (tileable)
image, one that repeats without a visible seam; any image works for a first try.

1. *Scene → New Scene*, pick *2D Scene*. The root is a `Node2D`.
2. Select the root, click *+ Add Child Node*, search "Camera2D", press *Create*. Keep its
   *Enabled* property on, so it is the view the game shows.
3. Right-click the root, choose *Instantiate Child Scene…* and pick
   `lf_infinite_scroll_sprite.tscn` from the library's folder. (Or *+ Add Child Node*, search
   "LFInfiniteScrollSprite", and in the Inspector turn on *Region → Enabled* and set
   *CanvasItem → Texture → Repeat* to *Enabled*.)
4. Select the new sprite and set these in the Inspector:
   - *Texture*: drag your image from the FileSystem dock.
   - *Region → Rect → Size*: the size of your game window in pixels, for example
     `1152` x `648` (the default window; see *Project Settings → Display → Window*). Without
     a size, nothing is drawn.
   - *Camera*: click *Assign…* and pick the `Camera2D`.
   - *Position Factor*: `0.25`. It means "move at a quarter of the camera's speed", so
     the layer looks far away. `1` keeps it fixed in the world, `0` pins it to the screen.
5. Select the `Camera2D`, click *Attach Script* (the scroll icon above the Scene dock),
   *Create*, and replace the contents with:

   ```gdscript
   extends Camera2D

   func _process(delta: float) -> void:   # delta = seconds since the last frame
   	position.x += 200.0 * delta          # move the camera right, 200 pixels per second
   ```
6. Save the scene and press *F6* (*Run Current Scene*).

You should see the texture slide to the left, slowly, as the camera travels right. For a
layer that drifts by itself with no camera, set its *Autoscroll* to `-20, 0`
(world units per second) instead. To drive several layers at once, see the controller in
Usage below.

## API

Everything the class offers; you only need the rows used above to get started.

### LFInfiniteScrollSprite — Constants

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_POSITION_FACTOR` | `const float = 1.0` | Default `position_factor`: the texture stays fixed in the world. |

### LFInfiniteScrollSprite — Exports

| Member | Signature | Description |
|---|---|---|
| `track_camera` | `bool = true` | When true and `camera` is set, the layer follows the camera itself every frame. A controller turns it off on its layers. |
| `camera` | `Camera2D` | Camera used for self-tracking and by `reset()`; use the viewport's current camera. Assigning it while the layer is in the tree calls `reset()`. |
| `position_factor` | `float = DEFAULT_POSITION_FACTOR` (1.0) | Multiplier applied to camera movement (parallax depth): `1` keeps the texture fixed in the world, `0` pins it to the screen. |
| `autoscroll` | `Vector2 = ZERO` | Velocity in world units per second at which the texture drifts on its own, independent of any camera and of `position_factor`. |
| `process_callback` | `Camera2D.Camera2DProcessCallback = CAMERA2D_PROCESS_IDLE` | Update on idle frames or on physics frames. Match the camera's own `process_callback`. |

### LFInfiniteScrollSprite — Properties / Methods

| Member | Signature | Description |
|---|---|---|
| `last_camera_position` | `Vector2` | The camera view centre self-tracking last saw; re-anchored by `reset()`. |
| `reset` | `reset() -> void` | Stores the centre of the camera's view into `last_camera_position` (no-op without a camera in the tree). Called from `_ready()` and the `camera` setter. |
| `apply_camera_delta` | `apply_camera_delta(delta: Vector2) -> void` | Scrolls by a world-space movement: `delta * position_factor` is converted into texels (texture pixels) through the layer's global transform (scale, rotation, skew) and its `flip_h`/`flip_v`, added to `region_rect.position` (incremental), then wrapped into `[0, texture size)` per axis. Does nothing on a layer scaled to zero or for a movement that is NaN or infinite. |

Self-tracking (when `track_camera` and `camera` is in the tree): each frame the layer
moves to the centre of what the camera shows (`Camera2D.get_screen_center_position()`,
so smoothing, `offset`, drag margins and limits are respected) and scrolls by how far
that centre moved since the previous frame, through `apply_camera_delta` (never an
absolute recomputation, so offsets applied from elsewhere are kept).

### LFBackgroundController — Exports / Properties / Methods

| Member | Signature | Description |
|---|---|---|
| `scroll_layers` | `@export Array[LFInfiniteScrollSprite]` | Layers that receive the camera delta. Null entries are skipped. Assigning the array turns off each layer's `track_camera`; layers appended later are taken over on the next update. |
| `camera` | `@export Camera2D` | Tracked camera; use the viewport's current camera. Assigning it calls `reset()`. |
| `follow_camera` | `@export bool = true` | Moves every layer to the centre of the camera's view each update. Turn it off for layers that already stay on screen (under a `CanvasLayer` or the camera). |
| `process_callback` | `@export Camera2D.Camera2DProcessCallback = CAMERA2D_PROCESS_IDLE` | Update on idle frames or on physics frames. |
| `last_camera_position` | `Vector2` | Camera view centre from the previous update. |
| `reset` | `reset() -> void` | Stores the centre of the camera's view into `last_camera_position` (no-op unless the camera is in the tree). Called from `_ready()` and the `camera` setter. |
| `update_infinite_scroll_layers` | `update_infinite_scroll_layers(camera_delta: Vector2) -> void` | Calls `apply_camera_delta(camera_delta)` on every non-null layer. |

Each update the controller reads the camera's view centre once, moves its layers there
(if `follow_camera`) and passes the movement since the last update to
`update_infinite_scroll_layers`.

## Usage

The same idea built from code, with two layers and a controller. A script on the root `Node2D` of a level that has a `Camera2D` child. Assign two
seamless (tileable) textures in the Inspector.

```gdscript
extends Node2D

@export var stars_texture: Texture2D   # a tileable texture, e.g. a starfield
@export var clouds_texture: Texture2D

@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	var view_size := get_viewport_rect().size

	# A far layer: moves at a quarter of the camera's speed.
	var stars := LFInfiniteScrollSprite.new()
	stars.texture = stars_texture
	stars.region_enabled = true                                  # required
	stars.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED     # required
	stars.region_rect = Rect2(Vector2.ZERO, view_size)           # the visible area; must not be zero
	stars.position_factor = 0.25
	stars.z_index = -10                                          # behind the level
	add_child(stars)

	# One controller drives every layer from the camera.
	var controller := LFBackgroundController.new()
	var layers: Array[LFInfiniteScrollSprite] = [stars]
	controller.scroll_layers = layers   # takes the layers over: their track_camera turns off
	controller.camera = camera
	add_child(controller)

	# A layer that drifts on its own, with no camera at all (a menu background):
	var clouds := LFInfiniteScrollSprite.new()
	clouds.texture = clouds_texture
	clouds.region_enabled = true
	clouds.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	clouds.region_rect = Rect2(Vector2.ZERO, view_size)
	clouds.autoscroll = Vector2(-20, 0)   # world units per second
	clouds.z_index = -5
	add_child(clouds)
```

A single layer can also follow the camera by itself, without a controller: set its
`camera` (and leave `track_camera` on).

## Notes

- The `.tscn` sets `texture_repeat = 2` (enabled) and `region_enabled = true`; when building from code, enable both yourself or the region shift has no visible effect.
- `region_rect.size` must be set: the script never sets it and the `.tscn` leaves it at zero, so the layer draws nothing until it is configured. Use the size of the view (in texels, i.e. divided by the layer's scale) with `centered = true`.
- Layers update at the end of the frame, after every node (the camera included) has processed, so a layer sits on the view the frame renders whatever the tree order. An unsmoothed camera moved during the frame is brought up to date with `force_update_scroll()` before it is read; a smoothing camera is read as it stepped during its own processing.
- Use the same `process_callback` as the camera; a physics-ticked layer behind an idle-moved camera judders whenever the frame rate exceeds the physics rate.
- A layer in a controller's `scroll_layers` stops tracking on its own (`track_camera = false`), so the camera's movement is applied once. Removing a layer from the controller leaves `track_camera` off.
- Assigning `camera` re-anchors, so tracking starts from the camera's current view instead of jumping by the whole camera position times `position_factor`. A camera that is not in the tree yet (or that leaves it for a while) is anchored on the first frame it is back.
- Give the layers and the controller the viewport's current camera: Godot updates the view only for that one, so another camera's view never moves.
- `region_rect.position` wraps modulo the texture size, also when the texture is swapped, so the offset stays within one tile however far the layer scrolls (the camera's own position is not wrapped). With no texture it is left unwrapped.
- Camera rotation is not followed; a self-tracking layer keeps its own rotation.
