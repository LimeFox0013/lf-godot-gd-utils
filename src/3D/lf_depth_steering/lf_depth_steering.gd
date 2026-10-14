## Depth steering for a 2.5D platformer: the player controls x and jump, the game moves the
## character in depth (z) so a jump ends on a platform and never runs into one from below.
##
## Pure maths on numbers and plain data. Y is up and `position` is the body's feet. Every
## physics frame while airborne: `landing` says where the fall will end, `dodge` says where to
## stand to clear what is overhead, and `step` eases the depth toward the chosen target.
class_name LFDepthSteering
extends RefCounted

## The body's half width and depth, when none is set.
const DEFAULT_BODY_RADIUS := 0.25
## The body's height from feet to head, when none is set.
const DEFAULT_BODY_HEIGHT := 1.58
## The feet's half width: how far they reach into a landing area, when none is set.
const DEFAULT_FOOT_HALF_X := 0.25
## Extra depth kept from a blocker beyond touching, when none is set.
const DEFAULT_CLEARANCE := 0.2
## Seconds of x movement a blocker check looks ahead, when none is set.
const DEFAULT_LOOK_AHEAD := 0.12
## `time_left` divided by this is the smoothing time of `step`, when none is set.
const DEFAULT_SMOOTH_DIVISOR := 3.5

## Depth distances at or below this count as arrived (and as a tie).
const ARRIVED_DISTANCE := 0.0001
## Heights closer than this count as the same height.
const SAME_HEIGHT := 0.0001
## The cubic-exponential approximation of `exp(-x)` used by the smooth damp.
const _EXP_QUADRATIC := 0.48
const _EXP_CUBIC := 0.235

static var _log := LFLogger.new(['LFDepthSteering'])

## The body's half width and depth.
var body_radius := DEFAULT_BODY_RADIUS
## The body's height from feet to head.
var body_height := DEFAULT_BODY_HEIGHT
## The feet's half width: a landing area is widened by this in x.
var foot_half_x := DEFAULT_FOOT_HALF_X
## Extra depth kept from a blocker beyond touching.
var clearance := DEFAULT_CLEARANCE
## Seconds of x movement a blocker check looks ahead.
var look_ahead := DEFAULT_LOOK_AHEAD
## `step` smooths over `time_left / smooth_divisor` seconds.
var smooth_divisor := DEFAULT_SMOOTH_DIVISOR


## A platform: its solid body (`center_x`, `half_x`, `center_z`, `half_z`, `bottom`, `top`)
## and the landing area around the same centre (`land_half_x`, `land_half_z`, surface at `top`).
class Footprint:
	extends RefCounted
	## Whatever the caller uses to tell footprints apart.
	var id: Variant = null
	var center_x := 0.0
	var half_x := 0.0
	var center_z := 0.0
	var half_z := 0.0
	var bottom := 0.0
	var top := 0.0
	var land_half_x := 0.0
	var land_half_z := 0.0


## Where a fall ends: the `footprint`, the seconds to touchdown (`time`) and the landing
## area's centre in depth (`z`).
class Landing:
	extends RefCounted
	var footprint: Footprint = null
	var time := 0.0
	var z := 0.0


## Where to stand to clear what is overhead (`z`) and the seconds until the earliest blocker
## meets the head (`time`).
class Dodge:
	extends RefCounted
	var z := 0.0
	var time := 0.0


## The height of the top of a jump from `height` rising at `velocity_up` under `gravity`;
## `height` itself when not rising.
static func apex_height(height: float, velocity_up: float, gravity: float) -> float:
	if velocity_up <= 0.0:
		return height
	return height + velocity_up * velocity_up / (2.0 * gravity)


## Seconds until the top of a jump; 0 when not rising.
static func time_to_apex(velocity_up: float, gravity: float) -> float:
	return maxf(velocity_up, 0.0) / gravity


## The footprint the fall reaches first: the highest `top` that is at or below the top of the
## jump and whose landing area (widened by `foot_half_x`) holds the feet's x at that moment.
## A falling body keeps its downward speed; a rising one falls from rest at the apex. `velocity_x` is held constant. Null when nothing lies below or the input is not finite.
func landing(position: Vector3, velocity_up: float, velocity_x: float, gravity_rise: float, gravity_fall: float, footprints: Array) -> Landing:
	if not _valid_flight(position, velocity_up, velocity_x, gravity_rise, gravity_fall) or footprints.is_empty():
		return null
	var apex_y := apex_height(position.y, velocity_up, gravity_rise)
	var apex_time := time_to_apex(velocity_up, gravity_rise)
	var fall_speed := maxf(-velocity_up, 0.0)
	var best: Footprint = null
	var best_time := 0.0
	for item: Footprint in footprints:
		if item.top > apex_y:
			continue
		var drop := apex_y - item.top
		var cross_time := apex_time + (sqrt(fall_speed * fall_speed + 2.0 * gravity_fall * drop) - fall_speed) / gravity_fall
		var reach := item.land_half_x + foot_half_x
		if absf(position.x + velocity_x * cross_time - item.center_x) > reach:
			continue
		if best == null or _higher_or_nearer(item, best, position.z):
			best = item
			best_time = cross_time
	if best == null:
		return null
	var result := Landing.new()
	result.footprint = best
	result.time = best_time
	result.z = best.center_z
	return result


## Where to stand so the body clears everything overhead, or null when nothing blocks (or
## the body is falling clear of everything). A footprint blocks when its height band meets
## the body's path up to the top of the jump (head included) and its x band meets where the
## body can be over `look_ahead`. The body leaves by the side it is on: the nearest free edge
## that does not cross a blocker's centre line. Only on a tie (dead centre) does it go toward
## `prefer_z`, else toward 0; boxed in between two centres it takes the nearest edge. `time` is the
## seconds until the earliest blocker's bottom meets the head, 0 when already level with it.
func dodge(position: Vector3, velocity_up: float, velocity_x: float, gravity_rise: float, footprints: Array, prefer_z: float) -> Dodge:
	if not _valid_flight(position, velocity_up, velocity_x, gravity_rise, 1.0) or not is_finite(prefer_z) or footprints.is_empty():
		return null
	var sweep_top := apex_height(position.y, velocity_up, gravity_rise) + body_height
	var x_ahead := position.x + velocity_x * look_ahead
	var x_low := minf(position.x, x_ahead) - body_radius
	var x_high := maxf(position.x, x_ahead) + body_radius
	var bands: Array[Vector2] = []
	var centers: Array[float] = []
	var earliest := INF
	for item: Footprint in footprints:
		if item.bottom >= sweep_top or item.top <= position.y:
			continue
		if item.center_x - item.half_x >= x_high or item.center_x + item.half_x <= x_low:
			continue
		var reach := item.half_z + body_radius + clearance
		bands.append(Vector2(item.center_z - reach, item.center_z + reach))
		centers.append(item.center_z)
		earliest = minf(earliest, _time_to_head(position.y + body_height, item.bottom, velocity_up, gravity_rise))
	if bands.is_empty():
		return null
	bands = _merged(bands)
	var inside_index := _band_index_containing(bands, position.z)
	if inside_index < 0:
		return null
	var result := Dodge.new()
	result.z = _free_edge(bands, centers, position.z, prefer_z)
	result.time = earliest
	return result


## The next depth (`x`) and depth velocity (`y`) of a critically damped follow of `target_z`
## that eases in and out, keeps the velocity across a target switch and never overshoots.
## The smoothing time is `max(time_left, delta) / smooth_divisor`; once `time_left <= delta`
## it lands on `target_z` exactly. A non-finite input returns `z` and `depth_velocity` unchanged.
func step(z: float, depth_velocity: float, target_z: float, delta: float, time_left: float) -> Vector2:
	var unchanged := Vector2(z, depth_velocity)
	if not (is_finite(z) and is_finite(depth_velocity) and is_finite(target_z) and is_finite(delta) and is_finite(time_left)) or delta < 0.0 or smooth_divisor <= 0.0:
		_log.error('step needs finite numbers, a delta of at least 0 and a positive smooth_divisor, got', z, depth_velocity, target_z, delta, time_left)
		return unchanged
	if time_left <= delta or absf(target_z - z) <= ARRIVED_DISTANCE:
		return Vector2(target_z, 0.0)
	var omega := 2.0 * smooth_divisor / maxf(time_left, delta)
	var scaled := omega * delta
	var decay := 1.0 / (1.0 + scaled + _EXP_QUADRATIC * scaled * scaled + _EXP_CUBIC * scaled * scaled * scaled)
	var change := z - target_z
	var carry := (depth_velocity + omega * change) * delta
	var next_velocity := (depth_velocity - omega * carry) * decay
	var next_z := target_z + (change + carry) * decay
	if (target_z - z > 0.0) == (next_z > target_z):
		return Vector2(target_z, 0.0)
	return Vector2(next_z, next_velocity)


func _valid_flight(position: Vector3, velocity_up: float, velocity_x: float, gravity_rise: float, gravity_fall: float) -> bool:
	var finite := position.is_finite() and is_finite(velocity_up) and is_finite(velocity_x) and is_finite(gravity_rise) and is_finite(gravity_fall)
	if not finite or gravity_rise <= 0.0 or gravity_fall <= 0.0:
		_log.error('a flight needs finite numbers and positive gravities, got', position, velocity_up, velocity_x, gravity_rise, gravity_fall)
		return false
	return true


func _higher_or_nearer(item: Footprint, best: Footprint, z: float) -> bool:
	if absf(item.top - best.top) <= SAME_HEIGHT:
		return absf(item.center_z - z) < absf(best.center_z - z)
	return item.top > best.top


func _time_to_head(head: float, bottom: float, velocity_up: float, gravity_rise: float) -> float:
	if bottom <= head or velocity_up <= 0.0:
		return 0.0
	var discriminant := velocity_up * velocity_up - 2.0 * gravity_rise * (bottom - head)
	if discriminant < 0.0:
		return INF
	return (velocity_up - sqrt(discriminant)) / gravity_rise


func _merged(bands: Array[Vector2]) -> Array[Vector2]:
	bands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = [bands[0]]
	for band in bands.slice(1):
		var last := merged[-1]
		if band.x <= last.y:
			merged[-1] = Vector2(last.x, maxf(last.y, band.y))
		else:
			merged.append(band)
	return merged


func _band_index_containing(bands: Array[Vector2], z: float) -> int:
	for index in bands.size():
		if z > bands[index].x and z < bands[index].y:
			return index
	return -1


func _free_edge(bands: Array[Vector2], centers: Array[float], z: float, prefer_z: float) -> float:
	var edges: Array[float] = []
	for band in bands:
		edges.append(band.x)
		edges.append(band.y)
	var valid: Array[float] = []
	for edge in edges:
		if not _crosses_center(centers, z, edge):
			valid.append(edge)
	if valid.is_empty():
		valid = edges
	var nearest := _nearest_gap(valid, z)
	var tied: Array[float] = []
	for edge in valid:
		if absf(edge - z) <= nearest + ARRIVED_DISTANCE:
			tied.append(edge)
	if tied.size() == 1:
		return tied[0]
	var side := signf(prefer_z - z)
	var toward: Array[float] = []
	for edge in tied:
		if side != 0.0 and signf(edge - z) == side:
			toward.append(edge)
	return _closest_to_zero(toward if not toward.is_empty() else tied)


func _crosses_center(centers: Array[float], z: float, edge: float) -> bool:
	var low := minf(z, edge)
	var high := maxf(z, edge)
	for center in centers:
		if center > low and center < high:
			return true
	return false


func _nearest_gap(candidates: Array[float], z: float) -> float:
	var best := INF
	for candidate in candidates:
		best = minf(best, absf(candidate - z))
	return best


func _closest_to_zero(candidates: Array[float]) -> float:
	var best := candidates[0]
	for candidate in candidates:
		if absf(candidate) < absf(best):
			best = candidate
	return best
