## A Control you can find from any script by a name you give it (its `registry_id`).
##
## While it is in the scene tree, the control is listed in one shared registry under its
## `registry_id`; `LFControl.by_id("that_id")` returns it from anywhere, with no node path and
## no SceneTree reference. It also has static helpers for UI placement: a control's
## centre, sorting controls into reading order, and placing a popup beside a rectangle.
## It is the base class of `LFLayoutControl`, `LFControl2D` and `LFControlOut`.
class_name LFControl
extends Control

## Key this control is registered under while in the tree, so it can be fetched with
## `LFControl.by_id(registry_id)`. Empty means it is never registered. Changing it while
## the control is in the tree moves the registration to the new key.
@export var registry_id: String:
	set(value):
		if value == registry_id:
			return
		if is_inside_tree():
			_unregister()
		registry_id = value
		if is_inside_tree():
			_register()


## Registration follows tree notifications rather than `_enter_tree`/`_exit_tree`, so
## a subclass overriding those without calling `super()` still registers and unregisters.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_register()
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			_unregister()


func _register() -> void:
	if registry_id.is_empty():
		return
	var holders: Array = _controls_registry.get(registry_id, [])
	holders.erase(self)
	holders.append(self)
	_controls_registry[registry_id] = holders


func _unregister() -> void:
	if registry_id.is_empty() or not _controls_registry.has(registry_id):
		return
	var holders: Array = _controls_registry[registry_id]
	holders.erase(self)
	if holders.is_empty():
		_controls_registry.erase(registry_id)


## id -> holders in registration order (the last one is the newest).
static var _controls_registry := {}

## Returns the newest control registered under `id` that is still alive and in the
## tree, or null if none is (also for an empty `id`). With `viewport`, only controls
## inside that viewport count, so the same id can be reused in several viewports (for
## example split-screen). Never returns a freed control.
static func by_id(id: String, viewport: Viewport = null) -> Control:
	if not _controls_registry.has(id):
		return null
	# Only controls inside the tree are listed: each one leaves the list on exiting the tree
	# (and on deletion), so every holder here is alive and in the tree.
	var holders: Array = _controls_registry[id]
	for i in range(holders.size() - 1, -1, -1):
		var control: Control = holders[i]
		if viewport == null or control.get_viewport() == viewport:
			return control
	return null


## Returns the centre of `control_node` in its own local (unscaled) coordinates: half its
## size.
static func get_center_pos(control_node: Control) -> Vector2:
	return control_node.size * 0.5


## Returns the on-screen centre of `control_node`, in its viewport's pixels. Scale,
## rotation, a CanvasLayer and a Camera2D are all taken into account (it goes through the
## control's full canvas transform).
static func get_center_pos_on_viewport(control_node: Control) -> Vector2:
	return control_node.get_global_transform_with_canvas() * (control_node.size * 0.5)


## Returns the on-screen rect of `control_node`, in its viewport's pixels: the bounding
## box of its rect mapped through its full canvas transform (a CanvasLayer's offset and
## scale, a Camera2D, the control's own scale and rotation). For an unrotated control on
## the default canvas with no Camera2D or canvas transform it equals `get_global_rect()`.
static func get_canvas_rect(control_node: Control) -> Rect2:
	return control_node.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control_node.size)


## Returns a new array of `controls` in reading order, row by row from the top, left to
## right within a row. Rows are built from the top down: a row starts at its highest
## control and takes every control whose top is at most `row_tolerance` px below that
## one's (by on-screen rect, `get_canvas_rect`, so controls on different canvas layers
## sort by where they are drawn). The result does not depend on the input order, except
## among controls in one row that share the same left edge (their order is unspecified).
## Entries that are not live Controls (null, freed, other types) are left out; the input
## array is not changed.
static func sort_reading_order(controls: Array, row_tolerance := 0.0) -> Array:
	var live := controls.filter(func(c: Variant) -> bool: return is_instance_valid(c) and c is Control)
	live.sort_custom(_reads_before)
	var sorted := []
	var row := []
	var row_top := 0.0
	for control: Control in live:
		var top := get_canvas_rect(control).position.y
		if not row.is_empty() and top - row_top > row_tolerance:
			row.sort_custom(_left_of)
			sorted.append_array(row)
			row.clear()
		if row.is_empty():
			row_top = top
		row.append(control)
	row.sort_custom(_left_of)
	sorted.append_array(row)
	return sorted


## Top to bottom, then left to right: a strict order, so sorting never sees a cycle.
static func _reads_before(a: Control, b: Control) -> bool:
	var ra := get_canvas_rect(a)
	var rb := get_canvas_rect(b)
	if ra.position.y != rb.position.y:
		return ra.position.y < rb.position.y
	return ra.position.x < rb.position.x


static func _left_of(a: Control, b: Control) -> bool:
	return get_canvas_rect(a).position.x < get_canvas_rect(b).position.x


## Returns the top-left position for a box of `box_size` placed beside `anchor`, inside
## an area of `bounds` size that starts at (0, 0) (all in the same coordinates). The box
## goes `gap` px to the right of `anchor`, or to its left when it would not fit on the
## right. It is top-aligned with `anchor`, moved to stay inside the area vertically when it
## is no taller than the area (a taller box is placed at y = 0 and overflows the bottom),
## and never placed left of 0: when it fits on neither side it goes to x = 0, where it may
## overlap `anchor` or overflow the right edge. Use it for popups, tooltips and callouts.
static func place_beside(anchor: Rect2, box_size: Vector2, bounds: Vector2, gap := 0.0) -> Vector2:
	var x := anchor.end.x + gap
	if x + box_size.x > bounds.x:
		x = anchor.position.x - gap - box_size.x
	var y := clampf(anchor.position.y, 0.0, maxf(bounds.y - box_size.y, 0.0))
	return Vector2(maxf(x, 0.0), y)
