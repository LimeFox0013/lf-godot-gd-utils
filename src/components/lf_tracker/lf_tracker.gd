## Keeps a HUD control on a 3D target, or on the screen edge pointing at it when the
## target is off screen.
##
## While the target is on screen, the control's pivot (`pivot_offset`) sits on the
## target's projection, the point where it appears on screen. While it is off screen (or
## behind the camera), the pivot sits where the line from the screen center toward the
## target meets a padded screen edge, and the control can rotate to point along that
## line. It signals on/off-screen changes and can hide itself on either side. Use it for
## off-screen direction arrows, or for labels and buttons that follow a 3D object.
## The target's own `visible` is not consulted: a hidden target is tracked like any other.
class_name LFTracker
extends Control

static var _log := LFLogger.new()

## Default `padding`: inset from each viewport edge, in pixels.
const DEFAULT_PADDING := 32.0
## Upper end of the inspector slider for `padding`, in pixels (larger values can be typed).
const _PADDING_SLIDER_MAX := 256.0
## Inspector slider step for `padding`, in pixels.
const _PIXEL_STEP := 1.0

## Emitted when the target goes from on-screen to off-screen (or behind the camera), and
## when an on-screen target is lost (set to null or freed).
signal screen_exited
## Emitted when the target goes from off-screen to on-screen.
signal screen_entered

## Camera used to project `target`. It must render into this control's viewport. While
## it is null, freed or outside the tree the tracker behaves as if it had no target.
@export var camera: Camera3D
## Tracked 3D node. While it is null, freed or outside the tree the tracker hides itself.
@export var target: Node3D
## Inset from each viewport edge, used for both the on-screen test and edge placement.
## Clamped to half the viewport's smaller side. At half that side or more, the padded
## rect has no area (a line or a point), so `on_screen` is true only for a target
## projected exactly onto it; this is reported once as a warning, and again only after
## the padding fitted in between.
@export_range(0.0, _PADDING_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var padding: float = DEFAULT_PADDING
## Hides the tracker while the target is on-screen (arrow indicators). While any hide
## flag is on, the tracker drives its own `visible`; with both off it leaves `visible`
## alone, except to hide while there is no target and to show itself again after it hid
## itself (a target came back, or the flag that hid it was turned off).
@export var hide_if_on_screen: bool = false
## Hides the tracker while the target is off-screen or behind the camera (panels and
## widgets that follow the target).
@export var hide_if_off_screen: bool = false
## When true, `rotation` points along the ray toward an off-screen target and the
## tracker stands upright (0 on screen, after undoing a rotated parent) while the target
## is on screen. When false, `rotation` is never written.
@export var rotate_to_target: bool = true

## True when the target was inside the padded rect and in front of the camera at the
## last evaluation; false before the first one. Read-only.
var on_screen: bool:
	get:
		return _on_screen
	set(_value):
		pass

var _on_screen := false
## False until the first evaluation with a target, which always reports its state.
var _evaluated := false
## True while the tracker is hidden because it has no target.
var _hidden_without_target := false
## True while a hide flag has hidden the tracker.
var _hidden_by_flag := false
## True once the padding leaving no on-screen area was reported; cleared when it fits.
var _reported_no_area := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	update_tracking()


## Evaluates the target now: on-screen state and signals, hide flags, placement and
## rotation. Called every frame; call it directly to place the tracker immediately.
## Does nothing while the tracker is outside the tree.
func update_tracking() -> void:
	if not is_inside_tree():
		return
	if not _has_target():
		_lose_target()
		return
	if _hidden_without_target:
		_hidden_without_target = false
		visible = true

	var viewport_size: Vector2 = get_viewport_rect().size
	var half_side: float = minf(viewport_size.x, viewport_size.y) * 0.5
	var inset: float = clampf(padding, 0.0, half_side)
	_report_padding(inset >= half_side, viewport_size)
	var padded_rect := Rect2(Vector2(inset, inset), viewport_size - Vector2(inset, inset) * 2.0)
	var world_position: Vector3 = target.global_position
	var projected: Variant = LFUtils3D.world_to_canvas_position(camera, world_position)
	var in_front: bool = projected != null
	var screen_point: Vector2 = projected if in_front else Vector2.ZERO

	var was_on_screen: bool = _on_screen
	_on_screen = in_front and _contains(padded_rect, screen_point)
	if not _evaluated:
		_evaluated = true
		was_on_screen = not _on_screen
	if was_on_screen and not _on_screen:
		screen_exited.emit()
	elif not was_on_screen and _on_screen:
		screen_entered.emit()

	if hide_if_off_screen or hide_if_on_screen:
		_hidden_by_flag = (hide_if_off_screen and not _on_screen) or (hide_if_on_screen and _on_screen)
		visible = not _hidden_by_flag
		if _hidden_by_flag:
			return
	elif _hidden_by_flag:
		_hidden_by_flag = false
		visible = true

	var angle := 0.0
	var point: Vector2 = screen_point
	if not _on_screen:
		var direction: Vector2 = LFUtils3D.screen_direction(camera, world_position)
		point = LFUtils2D.rect_edge_point(padded_rect, direction)
		angle = direction.angle()
	var parent_to_viewport: Transform2D = _parent_to_viewport()
	position = parent_to_viewport.affine_inverse() * point - pivot_offset
	if rotate_to_target:
		rotation = angle - parent_to_viewport.get_rotation()


## Warns once when the padding leaves no on-screen area; re-arms once it fits again.
func _report_padding(no_area: bool, viewport_size: Vector2) -> void:
	if not no_area:
		_reported_no_area = false
		return
	if _reported_no_area:
		return
	_reported_no_area = true
	_log.warning('LFTracker "%s": padding %s leaves no on-screen area in a %s viewport, so on_screen is true only for a target projected exactly onto the padded line or point; lower padding below %s' \
		% [name, padding, viewport_size, minf(viewport_size.x, viewport_size.y) * 0.5])


func _has_target() -> bool:
	return is_instance_valid(target) and target.is_inside_tree() \
		and is_instance_valid(camera) and camera.is_inside_tree()


func _lose_target() -> void:
	if _on_screen:
		_on_screen = false
		screen_exited.emit()
	_evaluated = false
	if visible:
		visible = false
		_hidden_without_target = true


## Inclusive on every side, so a padded rect shrunk to a line or a point still contains
## the points on it.
static func _contains(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.y >= rect.position.y \
		and point.x <= rect.end.x and point.y <= rect.end.y


## The transform from the parent's space into viewport pixels.
func _parent_to_viewport() -> Transform2D:
	return get_global_transform_with_canvas() * get_transform().affine_inverse()
