## One layer of an endless scrolling background: a Sprite2D whose repeating texture
## slides as the camera moves (or drifts on its own).
##
## The layer can follow a camera itself (self-tracking: it sits on the centre of what the
## camera shows) or be driven by an LFBackgroundController through `apply_camera_delta`.
## Movement is measured in world units and converted into texels (texture pixels)
## through the layer's own transform, so with `position_factor = 1` the texture stays
## fixed in the world whatever the layer's scale, rotation or flip. It scrolls by
## shifting `region_rect`, so turn on `region_enabled`, set `texture_repeat` to enabled
## and give the region a size (the packaged `.tscn` does the first two). The region
## offset wraps modulo the texture size.
class_name LFInfiniteScrollSprite
extends Sprite2D

## Default `position_factor`: 1 keeps the texture fixed in the world.
const DEFAULT_POSITION_FACTOR := 1.0

## Upper end of the Inspector slider for `position_factor` (a unitless multiplier;
## larger typed values are allowed).
const _POSITION_FACTOR_HINT_MAX := 2.0
## Step of the Inspector slider for `position_factor` (unitless).
const _POSITION_FACTOR_HINT_STEP := 0.01

## When true and `camera` is set, the layer follows the camera itself every frame.
## An LFBackgroundController turns this off on the layers it drives.
@export var track_camera := true
## Camera used for self-tracking and by `reset()`; it should be its viewport's current
## camera. Assigning it while the layer is in the tree calls `reset()`, so tracking
## starts from the camera's current view; a camera that is not in the tree yet is
## anchored on the first frame it is.
@export var camera: Camera2D:
	set(value):
		camera = value
		_anchored = false
		if is_inside_tree():
			reset()
## Multiplier applied to camera movement before it scrolls the texture (parallax depth):
## 1 keeps the texture fixed in the world, 0 pins it to the screen, values in between
## make a far-away layer that moves slower than the foreground.
@export_range(0.0, _POSITION_FACTOR_HINT_MAX, _POSITION_FACTOR_HINT_STEP, "or_greater", "or_less") var position_factor := DEFAULT_POSITION_FACTOR
## Velocity, in world units per second, at which the texture drifts on its own
## (independent of any camera and of `position_factor`).
@export var autoscroll := Vector2.ZERO
## When the layer updates: on idle frames (default, like Camera2D) or on physics frames.
## Match the camera's own `process_callback`.
@export var process_callback: Camera2D.Camera2DProcessCallback = Camera2D.CAMERA2D_PROCESS_IDLE:
	set(value):
		process_callback = value
		LFUtils2D.apply_process_callback(self, value)

## The camera view centre self-tracking last saw; reset() re-anchors it.
var last_camera_position := Vector2.ZERO

var _tick_queued := false
# Whether last_camera_position holds this camera's view; cleared while the camera is
# missing, so a camera that (re)appears is anchored instead of scrolled by its position.
var _anchored := false


func _init() -> void:
	texture_changed.connect(_wrap_region)


func _ready() -> void:
	process_callback = process_callback
	reset()


func _process(delta: float) -> void:
	_queue_tick(delta)


func _physics_process(delta: float) -> void:
	_queue_tick(delta)


## Re-anchors `last_camera_position` at the centre of the camera's view, so the next
## frame scrolls only movement made from now on (use it after teleporting the camera).
## Does nothing without a camera in the tree.
func reset() -> void:
	if LFUtils2D.camera_ready(camera):
		last_camera_position = LFUtils2D.settled_view_center(camera)
		_anchored = true


## Scrolls the texture by a world-space camera movement `delta`: shifts
## `region_rect.position` by `delta * position_factor`, converted into texels
## (incremental: it adds to the current offset, never sets it). The offset wraps into
## [0, texture size) per axis, which a repeating texture hides; without a texture it is
## not wrapped. A movement that is not finite (NaN or infinite) is ignored.
func apply_camera_delta(delta: Vector2) -> void:
	_shift_region(delta * position_factor)


# The layer reads the camera at the end of the frame, after every node (the camera
# included) has processed, so it matches the view that frame renders whatever the
# tree order.
func _queue_tick(delta: float) -> void:
	var camera_ready := LFUtils2D.camera_ready(camera)
	if not camera_ready:
		_anchored = false
	if _tick_queued:
		return
	if autoscroll == Vector2.ZERO and !(track_camera and camera_ready):
		return
	_tick_queued = true
	_tick.call_deferred(delta)


func _tick(delta: float) -> void:
	_tick_queued = false
	if autoscroll != Vector2.ZERO:
		_shift_region(-autoscroll * delta)
	if track_camera and LFUtils2D.camera_ready(camera):
		var center := LFUtils2D.settled_view_center(camera)
		if not _anchored:
			last_camera_position = center
			_anchored = true
		var camera_delta := center - last_camera_position
		last_camera_position = center
		global_position = center
		apply_camera_delta(camera_delta)


func _shift_region(world_delta: Vector2) -> void:
	if not world_delta.is_finite():
		return # one NaN or infinite offset would stay in the region for good
	var xform: Transform2D = global_transform if is_inside_tree() else transform
	if is_zero_approx(xform.determinant()):
		return # a layer scaled to zero shows no texels to scroll
	var texels: Vector2 = xform.affine_inverse().basis_xform(world_delta)
	if flip_h:
		texels.x = -texels.x
	if flip_v:
		texels.y = -texels.y
	region_rect.position += texels
	_wrap_region()


func _wrap_region() -> void:
	if texture == null:
		return
	var tile := texture.get_size()
	var region_offset := region_rect.position
	if tile.x > 0.0:
		region_offset.x = fposmod(region_offset.x, tile.x)
	if tile.y > 0.0:
		region_offset.y = fposmod(region_offset.y, tile.y)
	region_rect.position = region_offset
