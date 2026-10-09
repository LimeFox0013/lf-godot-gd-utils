## Finds a free spot near a point, so agents sent to the same place stand side by side instead of on top of each other.
##
## The answer is the point itself when nothing occupies it, otherwise the closest free
## position on successive rings around it, so a group heading for one point settles into
## a packed disc. `find_slot` keeps no state between calls: occupancy is read from an
## `LFSpatialIndex`, so it is exactly as current as the positions registered there.
## `Arrival` keeps one agent's spot steady, and `Claims` stops agents that pick at the same
## moment from picking the same spot while free spots remain.
class_name LFRingSlots

static var _log := LFLogger.new()


## Default distance between neighboring spots (and between rings), in world units.
const DEFAULT_SPACING := 1.0
## Default number of rings searched around the point. Bounds the search; with every ring full the result degrades to the outermost ring's
## point nearest the arrival. Ring n holds about 2π × n candidates, so the candidates
## checked grow with the square of the rings searched.
const DEFAULT_MAX_RINGS := 5

## An occupant within this fraction of `spacing` of a spot, on the XZ plane, takes it.
const _TAKEN_FRACTION := 0.5
## The fewest candidates a ring ever has.
const _MIN_RING_COUNT := 6
## Below this length, an arrival direction counts as none (world units).
const _MIN_DIRECTION_LENGTH := 0.001


## `center` when nothing occupies it; otherwise the free ring position nearest `from`,
## searching rings `spacing` apart outward, so an arrival keeps to the side it comes from.
## `exclude` is the one key in `spatial_index` to ignore (compared by value; a key of
## another type never matches). An occupant takes a spot when it stands within
## `spacing / 2` of it on the XZ plane and less than `spacing` above or below it — a body
## standing over a point takes it, one on another level does not. Queries `spatial_index`
## once for the whole search. With `claims`, a spot another claimant has claimed counts as
## taken the same way, whether or not anything stands there yet, so arrivals that pick
## their spots before reaching them don't all pick the same one. A non-finite `from`
## counts as coming from `center`. A null `spatial_index` counts as nothing standing
## anywhere (only `claims` take spots). A `spacing` that is not finite and
## positive is reported and answers `center`.
static func find_slot(
	center: Vector3,
	from: Vector3,
	spatial_index: LFSpatialIndex,
	exclude: Variant,
	spacing := DEFAULT_SPACING,
	max_rings := DEFAULT_MAX_RINGS,
	claims: Claims = null,
) -> Vector3:
	if !(spacing > 0.0 and is_finite(spacing)):
		_log.error("LFRingSlots.find_slot: spacing must be finite and positive, got %s" % spacing)
		return center
	var search_radius := maxi(max_rings, 0) * spacing + spacing * _TAKEN_FRACTION
	var occupied := PackedVector2Array()
	var standing: Array = [] if spatial_index == null else spatial_index.query_radius(center, Vector2(search_radius, spacing).length())
	for occupant: Variant in standing:
		# Different Variant types never match (and `==` across some of them is a script error).
		if typeof(occupant) == typeof(exclude) and occupant == exclude:
			continue
		var position: Vector3 = spatial_index.position_of(occupant)
		if absf(position.y - center.y) < spacing:
			occupied.append(Vector2(position.x, position.z))
	if claims != null:
		for claimed in claims._others(exclude):
			if absf(claimed.y - center.y) < spacing:
				occupied.append(Vector2(claimed.x, claimed.z))

	var center_xz := Vector2(center.x, center.z)
	var reach_squared := spacing * spacing * (_TAKEN_FRACTION * _TAKEN_FRACTION)
	if _is_free(center_xz, occupied, reach_squared):
		return center

	var from_xz := Vector2(from.x, from.z)
	if !from_xz.is_finite():
		from_xz = center_xz
	for ring in range(1, max_rings + 1):
		var best := Vector2.ZERO
		var best_distance := INF
		for offset in _unit_ring(ring):
			var candidate := center_xz + offset * spacing
			if !_is_free(candidate, occupied, reach_squared):
				continue
			var distance := candidate.distance_squared_to(from_xz)
			if distance < best_distance:
				best_distance = distance
				best = candidate
		if best_distance < INF:
			return Vector3(best.x, center.y, best.y)

	return _closest_on_ring(center, maxi(max_rings, 0) * spacing, from_xz)


## The candidate positions of the ring of `radius` around `center`, about `spacing`
## apart. Always an even count (at least 6), so the ring mirrors onto itself across both
## axes — an odd ring settles a group differently on its two sides. A `spacing` that is not
## finite and positive is reported and gives none.
static func ring_candidates(center: Vector3, radius: float, spacing: float) -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	if !(spacing > 0.0 and is_finite(spacing)):
		_log.error("LFRingSlots.ring_candidates: spacing must be finite and positive, got %s" % spacing)
		return candidates
	var count := _count_for(radius / spacing)
	for i in count:
		candidates.append(LFUtils3D.point_on_circle_xz(center, radius, i * TAU / count))
	return candidates


## Rings 1 to this many are built once, when the class loads; a search going further
## out builds the extra rings per call instead of caching them.
const _PREBUILT_RINGS := 16

## Index `ring`: that ring's candidates at a spacing of 1, around the origin — the same
## for every search. Filled once by the static initializer and never written again, so
## `find_slot` writes no static state.
static var _unit_rings: Array[PackedVector2Array] = _build_unit_rings(_PREBUILT_RINGS)


static func _build_unit_rings(count: int) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = [PackedVector2Array()]
	for ring in range(1, count + 1):
		rings.append(_build_unit_ring(ring))
	return rings


static func _unit_ring(ring: int) -> PackedVector2Array:
	if ring < _unit_rings.size():
		return _unit_rings[ring]
	return _build_unit_ring(ring)


static func _build_unit_ring(ring: int) -> PackedVector2Array:
	var built := PackedVector2Array()
	var count := _count_for(ring)
	for i in count:
		var angle := i * TAU / count
		built.append(Vector2(cos(angle), sin(angle)) * ring)
	return built


static func _count_for(rings_out: float) -> int:
	return maxi(_MIN_RING_COUNT, 2 * floori(TAU * rings_out / 2.0))


static func _is_free(position: Vector2, occupied: PackedVector2Array, reach_squared: float) -> bool:
	for occupant in occupied:
		if occupant.distance_squared_to(position) < reach_squared:
			return false
	return true


static func _closest_on_ring(center: Vector3, radius: float, from_xz: Vector2) -> Vector3:
	var direction := from_xz - Vector2(center.x, center.z)
	if direction.length() < _MIN_DIRECTION_LENGTH:
		direction = Vector2.RIGHT
	direction = direction.normalized() * radius
	return center + Vector3(direction.x, 0.0, direction.y)


## Spots promised to claimants before they reach them, shared by everything picking
## spots in one place — one per claimant. Pass it to `find_slot` (or set it on each
## `Arrival`) so a spot one arrival is still walking to counts as taken for the rest.
## A claimant that is a freed Object is forgotten on the next search.
class Claims extends RefCounted:
	## claimant -> its claimed spot (Vector3).
	var _slots: Dictionary = {}

	## Records `slot` as `claimant`'s spot, replacing any spot it held.
	func claim(claimant: Variant, slot: Vector3) -> void:
		_slots[claimant] = slot

	## Drops `claimant`'s spot; nothing happens when it holds none.
	func release(claimant: Variant) -> void:
		_slots.erase(claimant)

	## `claimant`'s spot, or null.
	func slot_of(claimant: Variant) -> Variant:
		return _slots.get(claimant)

	## How many spots are claimed.
	func size() -> int:
		return _slots.size()

	## Drops every claim.
	func clear() -> void:
		_slots.clear()

	## Every claimed spot but `claimant`'s own, forgetting freed claimants on the way.
	func _others(claimant: Variant) -> Array[Vector3]:
		var found: Array[Vector3] = []
		for key: Variant in _slots.keys():
			if typeof(key) == TYPE_OBJECT and !is_instance_valid(key):
				_slots.erase(key)
				continue
			if typeof(key) == typeof(claimant) and key == claimant:
				continue
			found.append(_slots[key])
		return found


## A committed arrival slot near a goal, with hysteresis: an arrival with no slot claims
## one (`find_slot`) once within `enter_radius` of the goal, and keeps it until it is
## farther than `exit_radius` — so a body jostled back and forth across one threshold
## does not drop and re-search its slot on every crossing. One per arriving body.
class Arrival extends RefCounted:
	## Within this distance of the goal, a body with no slot claims one.
	var enter_radius: float
	## A body holding a slot drops it only beyond this distance (at least `enter_radius`).
	var exit_radius: float
	## Passed to `find_slot`.
	var spacing: float
	## Passed to `find_slot`.
	var max_rings: int
	## Shared with the other arrivals heading for the same places: the slot this arrival
	## holds is claimed in it under `exclude`, so two arrivals entering the zone together
	## don't commit to the same spot while a free one remains within `max_rings` (with every
	## ring full, they can share the fallback point). Null: only bodies already standing
	## count.
	var claims: Claims = null

	var _slot: Variant = null
	var _goal: Variant = null
	var _claimant: Variant = null
	## The Claims `_claimant` holds a spot in (null: none), kept so the claim is released
	## there even after `claims` is reassigned, and even when the claimant key is null.
	var _claimed_in: Claims = null

	## An arrival claiming slots `initial_spacing` apart inside `initial_enter_radius`, held
	## out to `initial_exit_radius` (raised to the enter radius when smaller).
	func _init(initial_enter_radius: float, initial_exit_radius: float, initial_spacing: float = DEFAULT_SPACING, initial_max_rings: int = DEFAULT_MAX_RINGS) -> void:
		enter_radius = initial_enter_radius
		exit_radius = maxf(initial_exit_radius, initial_enter_radius)
		spacing = initial_spacing
		max_rings = initial_max_rings

	## Where a body at `from` heading for `goal` should walk: its committed slot while
	## inside the arrival zone (claiming one from `index`, ignoring `exclude`, on entry),
	## or null outside it — steer by other means there. `extra_ok` false counts as
	## outside the zone (for a caller's own condition, such as the goal being on another
	## level) and drops the slot. A different `goal` from last call drops the slot too.
	func destination(goal: Vector3, from: Vector3, index: LFSpatialIndex, exclude: Variant, extra_ok := true) -> Variant:
		if _goal != goal:
			_drop()
			_goal = goal
		var radius := exit_radius if _slot != null else enter_radius
		if !extra_ok or !(from.distance_to(goal) <= radius):
			_drop()
			return null
		if _slot == null:
			_slot = LFRingSlots.find_slot(goal, from, index, exclude, spacing, max_rings, claims)
			if claims != null:
				claims.claim(exclude, _slot)
				_claimant = exclude
				_claimed_in = claims
		return _slot

	## The committed slot, or null.
	func slot() -> Variant:
		return _slot

	## Drops the committed slot (and its claim); the next `destination` inside the enter
	## radius claims a new one.
	func reset() -> void:
		_drop()
		_goal = null

	func _drop() -> void:
		_slot = null
		if _claimed_in != null:
			_claimed_in.release(_claimant)
		_claimed_in = null
		_claimant = null
