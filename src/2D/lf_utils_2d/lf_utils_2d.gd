## Small helpers for nodes that follow a Camera2D, plus one piece of screen geometry.
##
## Answers whether a camera can be read, the centre and world rect of what it shows this
## frame, switches a node between idle and physics processing to match a camera, and
## finds where a ray from a rect's centre meets its border. All functions are static:
## call them on the class (`LFUtils2D.camera_ready(camera)`), never create an instance.
class_name LFUtils2D

static var _log := LFLogger.new()


## True when `camera` is a live Camera2D inside the tree, the only state in which its
## view can be read. False for null, a freed camera or one not added to the tree.
## (Godot computes the view only for the viewport's current camera, so the view
## functions below describe what the viewport shows: give them the current camera.)
## The camera parameters of this class are untyped on purpose: GDScript reports an error
## when a freed object is passed to a typed parameter, so a typed one could not take the
## freed camera these functions answer. Anything else that is not a Camera2D (a live
## Node2D, a number...) is a mistake: it counts as no camera and is reported as an error
## through `LFLogger`, by every function below that is given it.
static func camera_ready(camera: Variant) -> bool:
	if not is_instance_valid(camera):
		if typeof(camera) != TYPE_NIL and typeof(camera) != TYPE_OBJECT:
			_log.error('LFUtils2D: expected a Camera2D, got a %s' % type_string(typeof(camera)))
		return false
	if not camera is Camera2D:
		_log.error('LFUtils2D: expected a Camera2D, got a %s' % (camera as Object).get_class())
		return false
	return (camera as Camera2D).is_inside_tree()


## Brings an unsmoothed camera's view up to date with a move made this frame, so reading
## it right away gives the new view. (A camera publishes its new view only once Godot
## handles its pending transform change.) A camera with position or rotation smoothing
## already stepped during its own processing; updating it again would advance the
## smoothing twice, so it is left alone. Does nothing unless `camera_ready(camera)`.
static func settle(camera: Variant) -> void:
	if not camera_ready(camera):
		return
	var camera_2d := camera as Camera2D
	if not camera_2d.position_smoothing_enabled and not camera_2d.rotation_smoothing_enabled:
		camera_2d.force_update_scroll()


## The world-space centre of what `camera` shows this frame (smoothing, `offset`, drag
## margins and limits included), after `settle(camera)`. `Vector2.ZERO` unless
## `camera_ready(camera)`. Only the viewport's current camera keeps this up to date;
## another camera answers the centre from when it was last current.
static func settled_view_center(camera: Variant) -> Vector2:
	if not camera_ready(camera):
		return Vector2.ZERO
	settle(camera)
	return (camera as Camera2D).get_screen_center_position()


## The camera's real view in world coordinates: the bounding box of the viewport's four
## corners mapped through the viewport's canvas transform, which the current camera
## sets (zoom, offset, rotation). For a camera that is not its viewport's current one
## this is still what the viewport shows, not that camera's view. An empty `Rect2()`
## unless `camera_ready(camera)`.
static func camera_world_rect(camera: Variant) -> Rect2:
	if not camera_ready(camera):
		return Rect2()
	var camera_2d := camera as Camera2D
	var viewport_rect: Rect2 = camera_2d.get_viewport().get_visible_rect()
	var to_world: Transform2D = camera_2d.get_canvas_transform().affine_inverse()
	var corners: PackedVector2Array = [
		to_world * viewport_rect.position,
		to_world * Vector2(viewport_rect.end.x, viewport_rect.position.y),
		to_world * viewport_rect.end,
		to_world * Vector2(viewport_rect.position.x, viewport_rect.end.y),
	]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for i in range(1, corners.size()):
		bounds = bounds.expand(corners[i])
	return bounds


## Makes `node` process on idle frames or on physics frames, the way a Camera2D with
## that `process_callback` does: turns one of `_process` / `_physics_process` on and the
## other off. Use it in the setter of a node's own `process_callback` export. Does
## nothing for a null or freed node (`node` is untyped so that a freed node can be passed
## without an error); anything else that is not a Node is reported as an error through
## `LFLogger` and left alone.
static func apply_process_callback(node: Variant, callback: Camera2D.Camera2DProcessCallback) -> void:
	if not is_instance_valid(node):
		if typeof(node) != TYPE_NIL and typeof(node) != TYPE_OBJECT:
			_log.error('LFUtils2D.apply_process_callback: expected a Node, got a %s' % type_string(typeof(node)))
		return
	if not node is Node:
		_log.error('LFUtils2D.apply_process_callback: expected a Node, got a %s' % (node as Object).get_class())
		return
	var target := node as Node
	target.set_process(callback == Camera2D.CAMERA2D_PROCESS_IDLE)
	target.set_physics_process(callback == Camera2D.CAMERA2D_PROCESS_PHYSICS)


## The point where the ray from `rect`'s centre along `direction` meets its border, for
## example to pin an off-screen arrow to the screen edge. The centre itself when
## `direction` is zero or not finite. `direction` need not be normalized (unit length):
## only its angle counts, however short it is. A rect with a negative size is read as
## the same area with a positive one.
static func rect_edge_point(rect: Rect2, direction: Vector2) -> Vector2:
	var area: Rect2 = rect.abs()
	var center: Vector2 = area.get_center()
	var half: Vector2 = area.size * 0.5
	var largest := maxf(absf(direction.x), absf(direction.y))
	if not direction.is_finite() or largest == 0.0:
		return center
	# Scaled up first: normalizing a direction near 1e-30 would underflow to zero.
	var unit: Vector2 = (direction / largest).normalized()
	var distance := INF
	if not is_zero_approx(unit.x):
		distance = minf(distance, half.x / absf(unit.x))
	if not is_zero_approx(unit.y):
		distance = minf(distance, half.y / absf(unit.y))
	if distance == INF:
		return center
	return center + unit * distance
