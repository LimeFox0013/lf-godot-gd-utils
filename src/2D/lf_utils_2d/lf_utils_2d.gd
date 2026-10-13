## Small helpers for nodes that follow a Camera2D, plus some 2D geometry and sprite sizing.
##
## Answers whether a camera can be read, the centre and world rect of what it shows this
## frame, switches a node between idle and physics processing to match a camera, finds
## where a ray from a rect's centre meets its border, picks random points in a circle or
## around a rect, measures how far apart a set of points spreads, and sizes a sprite or reads
## a collision shape's size, builds a click mask from a texture's alpha, steers a character
## or rigid body toward a direction, and knocks a rigid body away from a point. All functions are static: call them on the class
## (`LFUtils2D.camera_ready(camera)`), never create an instance.
class_name LFUtils2D

## The default `scale_range` of `random_point_outside_rect`: the border 10% to 40% larger than the rect.
const DEFAULT_OUTSIDE_SCALE_RANGE := Vector2(1.1, 1.4)

## The alpha at or below which `alpha_click_mask` counts a pixel as transparent (not clickable).
const DEFAULT_ALPHA_THRESHOLD := 0.1
## The share of `speed` per second that `steer` accelerates a CharacterBody2D by: 0.7 reaches
## full speed in a little over a second.
const DEFAULT_STEER_ACCELERATION_RATIO := 0.7
## How strongly `steer` pushes a RigidBody2D toward its wanted velocity: the force is the
## velocity gap times the body's mass times this, so the gap closes in about 1 / this seconds.
const DEFAULT_STEER_FORCE_GAIN := 10.0

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


## A uniformly random point in the disc of `radius` around `center` (uniform by area, so
## points do not bunch up near the centre). Rolls from `rng` when given (a seeded caller's
## own generator), else the global one. A zero radius returns `center`.
static func random_point_in_circle(center: Vector2, radius: float, rng: RandomNumberGenerator = null) -> Vector2:
	var angle := rng.randf_range(0.0, TAU) if rng != null else randf_range(0.0, TAU)
	var distance := sqrt(rng.randf() if rng != null else randf()) * radius
	return center + Vector2.from_angle(angle) * distance


## A random point on the border of `rect` scaled about its centre by a factor drawn
## uniformly from `scale_range` (min, max), for example to spawn enemies just outside the
## screen: pass `LFUtils2D.camera_world_rect(camera)`. One of the four sides is chosen with
## equal probability whatever its length, then a point along it. A factor above 1 puts the
## point outside `rect`, below 1 inside. A negative-size rect is read as the same area with
## a positive size. Rolls from `rng` when given, else the global generator.
static func random_point_outside_rect(rect: Rect2, scale_range: Vector2 = DEFAULT_OUTSIDE_SCALE_RANGE, rng: RandomNumberGenerator = null) -> Vector2:
	var factor := rng.randf_range(scale_range.x, scale_range.y) if rng != null else randf_range(scale_range.x, scale_range.y)
	var side := rng.randi_range(0, 3) if rng != null else randi_range(0, 3)
	var along := rng.randf() if rng != null else randf()
	var area: Rect2 = rect.abs()
	var half: Vector2 = area.size * 0.5 * factor
	var center: Vector2 = area.get_center()
	match side:
		0:
			return Vector2(center.x + lerpf(-half.x, half.x, along), center.y - half.y)
		1:
			return Vector2(center.x + half.x, center.y + lerpf(-half.y, half.y, along))
		2:
			return Vector2(center.x + lerpf(half.x, -half.x, along), center.y + half.y)
	return Vector2(center.x - half.x, center.y + lerpf(half.y, -half.y, along))


## The largest distance between any two of `points` (their diameter): 0.0 for fewer than two
## points. Points with a NaN or infinite coordinate are ignored. It builds the convex hull
## (the outline that wraps all the points), then compares every pair of points on it: the
## farthest pair is always on the hull, so interior points are never compared.
static func max_pairwise_distance(points: PackedVector2Array) -> float:
	var sorted: Array[Vector2] = []
	for point in points:
		if point.is_finite():
			sorted.append(point)
	if sorted.size() < 2:
		return 0.0
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y if a.x == b.x else a.x < b.x)
	var hull := _convex_hull(sorted)
	var widest_squared := 0.0
	for i in hull.size():
		for j in range(i + 1, hull.size()):
			widest_squared = maxf(widest_squared, hull[i].distance_squared_to(hull[j]))
	return sqrt(widest_squared)


## Scales `sprite` so its texture shows at `size` in pixels (the visible region, for a
## sprite sheet or a region): sets `scale`, keeping the sign of each axis, so a sprite
## flipped with a negative scale stays flipped. Returns false, reports an error through
## `LFLogger` and changes nothing for a null sprite, one without a texture, or one whose
## texture is empty. `size` is the on-screen size before any parent scale.
static func fit_sprite_to_size(sprite: Sprite2D, size: Vector2) -> bool:
	if sprite == null:
		_log.error('LFUtils2D.fit_sprite_to_size: no sprite')
		return false
	if sprite.texture == null:
		_log.error('LFUtils2D.fit_sprite_to_size: the sprite has no texture to measure')
		return false
	var texture_size: Vector2 = sprite.get_rect().size
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		_log.error('LFUtils2D.fit_sprite_to_size: the sprite shows an empty area')
		return false
	var wanted: Vector2 = size / texture_size
	sprite.scale = Vector2(
		-absf(wanted.x) if sprite.scale.x < 0.0 else absf(wanted.x),
		-absf(wanted.y) if sprite.scale.y < 0.0 else absf(wanted.y),
	)
	return true


## The width and height of the box around `shape_node`'s shape, in the shape's own units
## (the node's scale is not applied): a circle is 2 x radius on both axes, a rectangle is
## its size, a capsule is 2 x radius by height. `Vector2.ZERO`, with an error through
## `LFLogger`, for a null node or one without a shape.
static func shape_size(shape_node: CollisionShape2D) -> Vector2:
	if shape_node == null or shape_node.shape == null:
		_log.error('LFUtils2D.shape_size: no collision shape')
		return Vector2.ZERO
	return shape_node.shape.get_rect().size


## A click mask for `texture`: a `BitMap` that is set where the pixel's alpha is above
## `threshold` (0.0 to 1.0, `DEFAULT_ALPHA_THRESHOLD`), so only the visible part of a
## sprite takes clicks. A compressed texture is decompressed first, on a copy of its image
## (the texture itself is not changed). Null, with an error through `LFLogger`, for a null
## texture, one without an image, a NaN threshold, or an image that cannot be decompressed.
## The mask has the size of the image, in pixels.
static func alpha_click_mask(texture: Texture2D, threshold := DEFAULT_ALPHA_THRESHOLD) -> BitMap:
	if texture == null:
		_log.error('LFUtils2D.alpha_click_mask: no texture')
		return null
	if is_nan(threshold):
		_log.error('LFUtils2D.alpha_click_mask: the threshold is NaN')
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		_log.error('LFUtils2D.alpha_click_mask: the texture has no image')
		return null
	if image.is_compressed():
		image = image.duplicate() # some textures hand out their own image, so never decompress it in place
		if image.decompress() != OK:
			_log.error('LFUtils2D.alpha_click_mask: the image could not be decompressed')
			return null
	var mask := BitMap.new()
	mask.create_from_image_alpha(image, threshold)
	return mask


## Makes `button` take clicks only on the visible pixels of its `texture_normal`: sets
## `texture_click_mask` to `alpha_click_mask(button.texture_normal, threshold)`. Returns
## false (and an error through `LFLogger`) for a null button or one without a
## `texture_normal`, leaving the button as it was. Call it again after changing the texture.
static func apply_alpha_click_mask(button: TextureButton, threshold := DEFAULT_ALPHA_THRESHOLD) -> bool:
	if button == null:
		_log.error('LFUtils2D.apply_alpha_click_mask: no button')
		return false
	var mask := alpha_click_mask(button.texture_normal, threshold)
	if mask == null:
		return false
	button.texture_click_mask = mask
	return true


## Accelerates `body` toward `direction` (any length: only its angle counts; a zero
## direction brakes toward standstill) at `speed` pixels per second, once per physics
## frame. A CharacterBody2D has its `velocity` moved toward the wanted velocity by
## `speed * acceleration_ratio * delta` and, when `slide` is true, then calls
## `move_and_slide()` (pass false to do your own move). A RigidBody2D gets a force of
## (wanted velocity - `linear_velocity`) * `mass` * `force_gain` applied with `apply_force`
## (`delta` is not used; call it from `_physics_process`). A negative `speed` counts as 0.
## Returns false, reporting an error through `LFLogger` and changing nothing, for a null or
## other kind of body, or a direction, speed, `delta`, ratio or gain that is NaN or infinite.
static func steer(body: Node2D, direction: Vector2, speed: float, delta: float, acceleration_ratio := DEFAULT_STEER_ACCELERATION_RATIO, force_gain := DEFAULT_STEER_FORCE_GAIN, slide := true) -> bool:
	if not (body is CharacterBody2D or body is RigidBody2D):
		_log.error('LFUtils2D.steer: expected a CharacterBody2D or RigidBody2D, got %s' % (body.get_class() if body != null else 'null'))
		return false
	if not (direction.is_finite() and is_finite(speed) and is_finite(delta) and is_finite(acceleration_ratio) and is_finite(force_gain)):
		_log.error('LFUtils2D.steer: direction, speed, delta, acceleration_ratio and force_gain must be finite numbers')
		return false
	var wanted: Vector2 = direction.normalized() * maxf(0.0, speed)
	if body is CharacterBody2D:
		var character := body as CharacterBody2D
		character.velocity = character.velocity.move_toward(wanted, maxf(0.0, speed) * acceleration_ratio * delta)
		if slide:
			character.move_and_slide()
	else:
		var rigid := body as RigidBody2D
		rigid.apply_force((wanted - rigid.linear_velocity) * rigid.mass * force_gain)
	return true


## Gives a RigidBody2D one impulse of `strength` away from `source_position` (a negative
## `strength` pulls it toward the point). False, with an error, for any other body or a
## non-finite number; false too for a body exactly on the point.
static func knock_back(body: Node2D, source_position: Vector2, strength: float) -> bool:
	if not body is RigidBody2D:
		_log.error('LFUtils2D.knock_back: expected a RigidBody2D, got %s' % (body.get_class() if body != null else 'null'))
		return false
	if not (source_position.is_finite() and is_finite(strength)):
		_log.error('LFUtils2D.knock_back: source_position and strength must be finite numbers')
		return false
	var away := body.global_position - source_position
	if away.is_zero_approx():
		return false
	(body as RigidBody2D).apply_central_impulse(away.normalized() * strength)
	return true


# Andrew's monotone chain over points already sorted by x then y: the hull without its
# collinear points, in order.
static func _convex_hull(sorted: Array[Vector2]) -> Array[Vector2]:
	var lower: Array[Vector2] = []
	for point in sorted:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], point) <= 0.0:
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector2] = []
	for i in range(sorted.size() - 1, -1, -1):
		var point := sorted[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], point) <= 0.0:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


# Twice the signed area of the triangle (origin, a, b): positive when b is left of origin -> a.
static func _cross(origin: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - origin).cross(b - origin)
