## Drives several LFInfiniteScrollSprite layers from one camera, for a parallax
## background.
##
## Each frame it reads how far the camera's view moved, passes that one movement to every
## layer (each scales it by its own `position_factor`) and keeps the layers on the
## camera's view. It takes its layers over: their own `track_camera` is turned off, so
## the movement is never applied twice.
class_name LFBackgroundController
extends Node2D

## Layers that receive the camera delta each frame; empty or freed entries are skipped.
## Assigning the array turns off each layer's own `track_camera`; layers appended later
## are taken over on the next update.
@export var scroll_layers: Array[LFInfiniteScrollSprite] = []:
	set(value):
		scroll_layers = value
		_claim_layers()
## The camera whose movement scrolls the layers; it should be its viewport's current
## camera. Assigning it calls `reset()`, so the first update forwards only the movement
## since then; a camera that is not in the tree yet is anchored on the first update it
## is. Without a camera in the tree the controller does nothing.
@export var camera: Camera2D:
	set(value):
		camera = value
		_anchored = false
		reset()
## When true, every layer is moved to the centre of the camera's view each frame.
## Turn it off for layers that already stay on screen (under a CanvasLayer or the camera).
@export var follow_camera := true
## When the controller updates: on idle frames (default, like Camera2D) or on physics
## frames. Match the camera's own `process_callback`.
@export var process_callback: Camera2D.Camera2DProcessCallback = Camera2D.CAMERA2D_PROCESS_IDLE:
	set(value):
		process_callback = value
		LFUtils2D.apply_process_callback(self, value)

## Camera view centre from the previous update, used to compute the delta.
var last_camera_position := Vector2.ZERO

var _tick_queued := false
# Whether last_camera_position holds this camera's view; cleared while the camera is
# missing, so a camera that (re)appears is anchored instead of forwarded as a jump.
var _anchored := false


func _ready() -> void:
	process_callback = process_callback
	reset()


func _process(_delta: float) -> void:
	_queue_tick()


func _physics_process(_delta: float) -> void:
	_queue_tick()


## Re-anchors `last_camera_position` at the centre of the camera's view, so the next
## update forwards only movement made from now on (use it after teleporting the camera).
## Does nothing without a camera in the tree.
func reset() -> void:
	if LFUtils2D.camera_ready(camera):
		last_camera_position = LFUtils2D.settled_view_center(camera)
		_anchored = true


## Scrolls every layer by a world-space movement: calls
## `apply_camera_delta(camera_delta)` on each layer in `scroll_layers` (empty or freed
## entries are skipped).
## Called each frame with the camera's movement; call it yourself to scroll from another
## source (a scripted speed, a 3D camera's motion).
func update_infinite_scroll_layers(camera_delta: Vector2) -> void:
	for layer in scroll_layers:
		if layer != null:
			layer.apply_camera_delta(camera_delta)


# Reads the camera at the end of the frame, after every node has processed, so the
# layers match the view that frame renders whatever the tree order.
func _queue_tick() -> void:
	if !LFUtils2D.camera_ready(camera):
		_anchored = false
		return
	if _tick_queued:
		return
	_tick_queued = true
	_tick.call_deferred()


func _tick() -> void:
	_tick_queued = false
	if !LFUtils2D.camera_ready(camera):
		return
	_claim_layers()
	var center := LFUtils2D.settled_view_center(camera)
	if not _anchored:
		last_camera_position = center
		_anchored = true
	var camera_delta := center - last_camera_position
	last_camera_position = center
	if follow_camera:
		for layer in scroll_layers:
			if layer != null:
				layer.global_position = center
	update_infinite_scroll_layers(camera_delta)


func _claim_layers() -> void:
	for layer in scroll_layers:
		if layer != null:
			layer.track_camera = false
