## A Camera2D that keeps a group of nodes in view: it sits at their average position and zooms
## out as they spread apart.
##
## Put the nodes in `targets` (two co-op players, a hero and its pets). Every frame the camera
## moves to the middle of the targets that still exist and eases its zoom between `max_zoom`
## (the group is close together) and `min_zoom` (the group is spread out), following how far
## apart the two most distant targets are. A freed or missing target is skipped, so it neither
## drags the middle toward the origin nor stops the camera. The math is in the static
## `framing` and `smoothed_zoom`, which need no scene. Zoom values are Godot's: the larger
## the number, the closer the view, so `min_zoom` is the widest view.
class_name LFGroupCamera2D
extends Camera2D


## The zoom used when the group is at least `max_spread` apart (the widest view), when none is set.
const DEFAULT_MIN_ZOOM := 0.5
## The zoom used when the group is no more than `min_spread` apart (the closest view), when none is set.
const DEFAULT_MAX_ZOOM := 1.0
## How quickly the zoom catches up with its goal, per second, when none is set.
const DEFAULT_ZOOM_SPEED := 2.0
## The smallest `min_zoom` the camera uses: a zoom of 0 or less is not a valid view.
const MIN_ZOOM_FLOOR := 0.01
## The derived `min_spread` is this fraction of the viewport's shorter side.
const DEFAULT_MIN_SPREAD_FRACTION := 0.5
## The derived `max_spread` is this fraction of the longer side of the area the farthest-out view shows.
const DEFAULT_MAX_SPREAD_FRACTION := 0.8

## The nodes to keep in view (`Node2D`s). Free ones are skipped; add and remove them as you like.
var targets: Array = []
## The widest view: the zoom when the group is `max_spread` apart or more. Values below
## `MIN_ZOOM_FLOOR` are read as that.
@export var min_zoom := DEFAULT_MIN_ZOOM
## The closest view: the zoom when the group is `min_spread` apart or less. At least `min_zoom`.
@export var max_zoom := DEFAULT_MAX_ZOOM
## The group spread (distance between the two most distant targets) up to which the view stays
## closest. 0 (or less) derives it from the viewport: half of its shorter side.
@export var min_spread := 0.0
## The group spread from which the view is widest. 0 (or less) derives it from the viewport: 0.8 of the
## longer side of the world area the widest view shows.
@export var max_spread := 0.0
## How fast the zoom catches up with its goal, per second (frame-rate independent). 0 or less
## freezes the zoom.
@export var zoom_speed := DEFAULT_ZOOM_SPEED
## Round the camera position to whole pixels, which stops sprites shimmering on pixel art.
@export var pixel_snap := false


## The pose that frames `positions`, as a Dictionary: `center` (Vector2, the average), `zoom`
## (float) and `spread` (float, the largest distance between two positions). `zoom_range` is
## (widest view, closest view) and `spread_range` is (closest-view spread, widest-view
## spread): the zoom is the closest at or below the first spread, the widest at or above the
## second, and in between it blends in a straight line. A `spread_range` whose second value
## is not above the first switches at that spread. Positions that are not finite are
## ignored; with none left the result is an empty Dictionary.
static func framing(positions: PackedVector2Array, zoom_range: Vector2, spread_range: Vector2) -> Dictionary:
	var valid := PackedVector2Array()
	var sum := Vector2.ZERO
	for point in positions:
		if point.is_finite():
			valid.append(point)
			sum += point
	if valid.is_empty():
		return {}
	var spread := LFUtils2D.max_pairwise_distance(valid)
	var span := spread_range.y - spread_range.x
	var blend := 0.0
	if span > 0.0:
		blend = clampf((spread - spread_range.x) / span, 0.0, 1.0)
	elif spread > spread_range.x:
		blend = 1.0
	return {
		'center': sum / valid.size(),
		'zoom': lerpf(zoom_range.y, zoom_range.x, blend),
		'spread': spread,
	}


## `current` moved toward `goal` by the fraction `1 - exp(-speed * delta)` of the gap: after
## one second the gap is the same share whether it took 1 step or 100. Returns `current`
## unchanged for a `speed` or `delta` of 0 or less, or any NaN.
static func smoothed_zoom(current: float, goal: float, speed: float, delta: float) -> float:
	if is_nan(current) or is_nan(goal) or is_nan(speed) or is_nan(delta) or speed <= 0.0 or delta <= 0.0:
		return current
	return lerpf(current, goal, 1.0 - exp(-speed * delta))


## The spreads used when `min_spread` and `max_spread` are 0, as (min, max), for a viewport of
## `viewport_size` pixels and the widest zoom `widest_zoom` (above 0; otherwise 1 is used):
## `DEFAULT_MIN_SPREAD_FRACTION` of the shorter viewport side, and `DEFAULT_MAX_SPREAD_FRACTION`
## of the longer side of the area the widest view shows.
static func default_spreads(viewport_size: Vector2, widest_zoom: float) -> Vector2:
	var widest := widest_zoom if widest_zoom > 0.0 else 1.0
	var widest_area := viewport_size / widest
	return Vector2(
		minf(viewport_size.x, viewport_size.y) * DEFAULT_MIN_SPREAD_FRACTION,
		maxf(widest_area.x, widest_area.y) * DEFAULT_MAX_SPREAD_FRACTION,
	)


## Adds `target` to `targets` unless it is null, freed or already there.
func add_target(target: Node2D) -> void:
	if is_instance_valid(target) and not targets.has(target):
		targets.append(target)


## Removes `target` from `targets`.
func remove_target(target: Node2D) -> void:
	targets.erase(target)


## The global positions of the targets that still exist and are inside the scene tree;
## freed, null and removed ones are left out (and dropped from `targets`).
func target_positions() -> PackedVector2Array:
	var positions := PackedVector2Array()
	var alive: Array = []
	for item: Variant in targets:
		if not is_instance_valid(item):
			continue
		alive.append(item)
		var target := item as Node2D
		if target != null and target.is_inside_tree():
			positions.append(target.global_position)
	targets = alive
	return positions


## Limits the camera to `rect` grown by `margin` on every side (Godot's `limit_left`,
## `limit_top`, `limit_right`, `limit_bottom`, rounded outward to whole pixels). A margin lets
## the view show a little beyond the edge of the map.
func set_world_rect(rect: Rect2, margin := 0.0) -> void:
	var area := rect.abs().grow(margin)
	limit_left = floori(area.position.x)
	limit_top = floori(area.position.y)
	limit_right = ceili(area.end.x)
	limit_bottom = ceili(area.end.y)


## Moves the camera to frame the targets now, easing the zoom by `delta` seconds
## (`delta <= 0` leaves the zoom as it is). Called every frame by the camera itself while it is
## `enabled`; call it yourself to step by hand. Does nothing with no targets left.
func update_framing(delta: float) -> void:
	var pose := _current_framing()
	if pose.is_empty():
		return
	global_position = _snapped(pose.center)
	var next := smoothed_zoom(zoom.x, pose.zoom, zoom_speed, delta)
	zoom = Vector2(next, next)


## Puts the camera at the framing of the targets at once, zoom included. Use it when the level
## starts, so the camera does not glide in from wherever it was.
func snap_to_targets() -> void:
	var pose := _current_framing()
	if pose.is_empty():
		return
	global_position = _snapped(pose.center)
	zoom = Vector2(pose.zoom, pose.zoom)


func _process(delta: float) -> void:
	if enabled:
		update_framing(delta)


func _current_framing() -> Dictionary:
	var widest := maxf(min_zoom, MIN_ZOOM_FLOOR)
	var spreads := Vector2(min_spread, max_spread)
	if min_spread <= 0.0 or max_spread <= 0.0:
		var derived := default_spreads(_viewport_size(), widest)
		spreads = Vector2(min_spread if min_spread > 0.0 else derived.x, max_spread if max_spread > 0.0 else derived.y)
	return framing(target_positions(), Vector2(widest, maxf(max_zoom, widest)), spreads)


func _viewport_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2.ZERO


func _snapped(point: Vector2) -> Vector2:
	return point.round() if pixel_snap else point
