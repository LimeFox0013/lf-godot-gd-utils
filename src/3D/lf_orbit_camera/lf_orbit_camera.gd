## A strategy-game (RTS) camera: pan across the ground, zoom in and out, orbit around a point.
##
## It reads no input itself: feed it pixel deltas from your own input code (mouse drag,
## wheel, a gamepad stick scaled to pixels). `rig` is a Node3D pivot on the ground; the
## camera hangs under it at a fixed local offset. Panning moves the rig along its own X/Z
## (so a drag feels the same at any orbit angle), scaled by the current distance (so it
## feels the same at any zoom); zooming scales the offset's length, proportionally and
## clamped; orbiting turns the rig's yaw (its turn around the vertical axis) around
## whatever point it is panned to. With a `mount` between the rig and the camera, the
## mount carries the offset instead, so a node between the mount and the camera (an
## `LFShaker`) can move the camera freely. Tunables are properties; a subclass can set its
## own in `_init`.
class_name LFOrbitCamera
extends RefCounted

## Default `min_distance`, in world units.
const DEFAULT_MIN_DISTANCE := 5.0
## Default `max_distance`, in world units.
const DEFAULT_MAX_DISTANCE := 100.0
## Default `pan_units_per_pixel`: world units per pixel of drag at distance 1.
const DEFAULT_PAN_UNITS_PER_PIXEL := 0.0018
## Default `zoom_step_fraction`: the fraction of the distance one zoom step moves.
const DEFAULT_ZOOM_STEP_FRACTION := 0.12
## Default `rotate_radians_per_pixel`: radians of yaw per pixel of orbit drag.
const DEFAULT_ROTATE_RADIANS_PER_PIXEL := 0.006

## The shortest starting offset (world units) read from the mount, so a zero offset
## never divides by zero.
const _MIN_OFFSET_LENGTH := 0.001

## The closest the camera may get to the rig, in world units. Takes effect on the next
## `zoom` or `frame`. Keep it at or below `max_distance`.
var min_distance := DEFAULT_MIN_DISTANCE
## The farthest the camera may get from the rig, in world units. Takes effect on the
## next `zoom` or `frame`.
var max_distance := DEFAULT_MAX_DISTANCE
## World units the rig moves per pixel of drag at distance 1; the actual step is this
## times the current distance, so a drag covers about the same share of the view at any
## zoom (how closely it tracks the ground also depends on the camera's field of view).
var pan_units_per_pixel := DEFAULT_PAN_UNITS_PER_PIXEL
## Fraction of the current distance one zoom-in step (amount 1) removes, so a step
## feels the same close in and far out. A zoom-out step divides the distance by
## `1 - zoom_step_fraction`, undoing one zoom-in step.
var zoom_step_fraction := DEFAULT_ZOOM_STEP_FRACTION
## Radians of yaw (turn around the vertical axis) per pixel of orbit drag.
var rotate_radians_per_pixel := DEFAULT_ROTATE_RADIANS_PER_PIXEL

## The ground pivot that pans and turns. The camera (or its mount) is its child.
var rig: Node3D
## The camera that renders the view; the one to project input rays through. May be
## swapped at any time; the offset keeps living on the mount set at construction.
var camera: Camera3D

## The node whose local position is the camera's offset from the rig: the mount, or the
## camera itself.
var _mount: Node3D
var _offset_direction: Vector3
var _distance: float


## `pivot` becomes `rig`, the node that pans and turns; `view_camera` becomes `camera`,
## sitting under the rig directly or under `mount`. The look direction and the starting
## distance are read from the mount's (or camera's) local position, so place it in the
## editor first. That position must not be zero: a zero offset leaves zoom with nothing
## to scale. `pivot` and `view_camera` must not be null.
func _init(pivot: Node3D, view_camera: Camera3D, mount: Node3D = null) -> void:
	rig = pivot
	camera = view_camera
	_mount = mount if mount != null else view_camera
	_distance = maxf(_mount.position.length(), _MIN_OFFSET_LENGTH)
	_offset_direction = _mount.position / _distance


## Returns the camera currently rendering the view (the `camera` property).
func get_camera() -> Camera3D:
	return camera


## Returns the node that carries the camera's offset from the rig: the mount passed to
## the constructor, or the camera when there was none.
func get_mount() -> Node3D:
	return _mount


## Returns the camera's current distance from the rig, in world units.
func distance() -> float:
	return _distance


## Pans the rig by a screen drag of `screen_delta` pixels: x along the rig's local X,
## y along its local Z, scaled by `pan_units_per_pixel` and the current distance. Which
## way that moves on screen depends on how the camera is turned under the rig; negate
## the delta for the other feel.
func pan(screen_delta: Vector2) -> void:
	var right := rig.transform.basis.x
	var forward := rig.transform.basis.z
	var step := pan_units_per_pixel * _distance
	rig.position += (right * screen_delta.x + forward * screen_delta.y) * step


## Zooms in (`amount` > 0) or out (< 0): multiplies the distance by
## `(1 - zoom_step_fraction) ^ amount`, clamped to [min_distance, max_distance], so
## `zoom(-n)` undoes `zoom(n)`. Never moves the rig. A NaN amount is ignored.
func zoom(amount: float) -> void:
	_set_distance(_distance * pow(1.0 - zoom_step_fraction, amount))


## Orbits the rig's yaw by a screen drag: `screen_delta.x` pixels times
## `rotate_radians_per_pixel` (dragging right turns clockwise seen from above). Never
## moves the rig.
func rotate(screen_delta: Vector2) -> void:
	rig.rotation.y -= screen_delta.x * rotate_radians_per_pixel


## Puts the rig over `center`, a world (global) point, keeping the rig's world height,
## and sets the camera's distance to `new_distance`, clamped to [min_distance,
## max_distance] — for a camera that frames a scene by itself (a cutscene, a "jump to
## point" button) instead of being steered. Works whatever the rig's parent transform; a
## rig outside the tree takes `center` as its local position. A NaN `new_distance` keeps
## the current distance.
func frame(center: Vector3, new_distance: float) -> void:
	if rig.is_inside_tree():
		rig.global_position = Vector3(center.x, rig.global_position.y, center.z)
	else:
		rig.position = Vector3(center.x, rig.position.y, center.z)
	_set_distance(new_distance)


func _set_distance(value: float) -> void:
	if is_nan(value):
		return
	_distance = clampf(value, min_distance, max_distance)
	_mount.position = _offset_direction * _distance
