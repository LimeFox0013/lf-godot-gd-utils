## Keeps the members of a 3D crowd from walking through each other, and lets them be knocked back.
##
## One per CharacterBody3D, layered on the body's own `move_and_slide()`: a knockback
## impulse that dies out, a push apart from neighbors that overlap it on the ground plane
## (separation), and weight blocking — a lighter body cannot push into a heavier one.
## Bodies in a crowd usually don't collide with each other physically (only with the
## ground and obstacles), so this is what keeps them from passing through one another.
##
## Neighbors come from an `LFSpatialIndex` every crowd body is registered in, instead
## of a physics overlap sensor (an Area3D) per body. `resolve` re-queries them only
## every `refresh_frames` frames, staggered randomly across bodies, and reuses the last
## list and push in between.
##
## Call order each physics frame, after your movement code sets `body.velocity` and
## before `move_and_slide()`:
## `body.velocity = crowd.velocity_with_knockback(delta)`, then `crowd.resolve(index)`.
## Both add to whatever `body.velocity` holds, so the movement code must assign it afresh
## every frame (zero when standing still): a body whose velocity is left as is carries
## last frame's knockback and push into this frame's, and they pile up.
class_name LFCrowdBody
extends RefCounted

## The metadata key a crowd body registers itself under on its body (`set_meta`), read by
## the default `peer_of` (`LFCrowdBody.of`).
const META := &"lf_crowd_body"
## Default `weight` of a new crowd body (any unit; only comparisons matter).
const DEFAULT_WEIGHT := 1.0
## Default `knockback_decay`, a fraction of the knockback speed lost per second.
const DEFAULT_KNOCKBACK_DECAY := 6.0
## Default `separation_radius`, in world units (centre to centre on the ground plane).
const DEFAULT_SEPARATION_RADIUS := 0.9
## Default `separation_strength`, push speed (units per second) per unit of overlap.
const DEFAULT_SEPARATION_STRENGTH := 3.0
## Default `neighbor_radius`, in world units (centre to centre in 3D).
const DEFAULT_NEIGHBOR_RADIUS := 1.0
## Default `refresh_frames`, in `resolve` calls between neighbor queries.
const DEFAULT_REFRESH_FRAMES := 3

## The smallest speed (units per second) the knockback decay is scaled by, so a nearly
## spent knockback still reaches zero in finite time.
const _MIN_DECAY_SPEED := 0.01
## Ground-plane distances (world units) below this count as zero: an exact overlap.
const _OVERLAP_EPSILON := 0.001
## A velocity's dot product with a blocker direction above this counts as heading into it.
const _HEADING_EPSILON := 0.00001

## The body this moves (its `velocity`). Not owned: freeing the body is the caller's
## business. Every method that reads or moves it needs it set (all but `of`,
## `apply_knockback`, `is_knocked_back` and `refresh_next`).
var body: CharacterBody3D
## How heavy this body is, in any unit you like (only comparisons matter). Blocking
## compares weights: a body is blocked by any heavier neighbor, never by a lighter or
## equal one.
var weight: float
## How fast a knockback dies out, as a fraction of its speed per second: 6 loses about
## a tenth of the speed per frame at 60 fps.
var knockback_decay := DEFAULT_KNOCKBACK_DECAY
## Neighbors closer than this (centre to centre, on the ground plane) are pushed apart;
## about twice a body's radius.
var separation_radius := DEFAULT_SEPARATION_RADIUS
## Push speed added per unit of overlap (how far inside `separation_radius` a neighbor
## is). Higher separates faster but can jitter.
var separation_strength := DEFAULT_SEPARATION_STRENGTH
## How far (centre to centre, in 3D) a body counts as a neighbor — about two bodies
## touching.
var neighbor_radius := DEFAULT_NEIGHBOR_RADIUS
## `resolve` re-queries neighbors once every this many calls; values below 1 become 1.
## Higher is cheaper for big crowds, lower reacts faster.
var refresh_frames := DEFAULT_REFRESH_FRAMES:
	set(value):
		refresh_frames = maxi(value, 1)
## Picks the push direction for exactly overlapping bodies, and staggers the first
## refresh. Null uses Godot's global generator; pass a seeded one for replays.
var rng: RandomNumberGenerator
## `peer_of(other_body) -> LFCrowdBody`: the crowd body of a neighbor, or null to ignore
## it for blocking. Defaults to `LFCrowdBody.of` (the body's `META` metadata). `resolve`
## asks it once per neighbor at each neighbor refresh and keeps the answer until the next
## one (each peer's `weight` is still read every call).
var peer_of: Callable = LFCrowdBody.of

var _knockback := Vector3.ZERO
var _frame := 0
var _neighbors: Array = []
var _push := Vector3.ZERO
# From `_neighbors` at each refresh: the other crowd bodies' bodies and their peers'
# instance ids (same slot) — what blocking needs every call, without asking `peer_of`
# again. Ids, not references: two neighbors holding each other would be a reference cycle
# that outlives their bodies.
var _peer_bodies: Array = []
var _peer_ids := PackedInt64Array()
# Reused by every blocking pass, so a frame allocates no array of its own.
var _blockers: Array[Vector3] = []


## Crowd physics for `character` (stored as `body`) weighing `body_weight` (stored as
## `weight`). Registers itself on the body as its `META` metadata so neighbors using the
## default `peer_of` find it. `rng` (stored as the `rng` property) picks directions for
## exact overlaps (null: the global generator). A null `character` makes a body-less peer,
## only useful as a weight for an injected `peer_of`.
@warning_ignore("shadowed_variable")
func _init(character: CharacterBody3D, body_weight := DEFAULT_WEIGHT, rng: RandomNumberGenerator = null) -> void:
	body = character
	weight = body_weight
	self.rng = rng
	_frame = rng.randi_range(0, refresh_frames - 1) if rng != null else randi_range(0, refresh_frames - 1)
	if character != null:
		character.set_meta(META, self)


## Returns the crowd body registered on `node` (its `META` metadata), or null when there
## is none or `node` is null, freed or not an object.
static func of(node: Variant) -> LFCrowdBody:
	if !is_instance_valid(node) or !node.has_meta(META):
		return null
	return node.get_meta(META) as LFCrowdBody


## Starts a knockback of `force` (a speed, units per second) along `direction` (any
## length; it is normalized), replacing any running one. It moves the body whatever its
## own movement does, and dies out over time. A zero `direction` cancels the knockback.
func apply_knockback(direction: Vector3, force: float) -> void:
	_knockback = direction.normalized() * force


## Returns `body.velocity` plus the running knockback, then lets the knockback decay by
## `delta` seconds. Call it once per physics frame and assign the result to
## `body.velocity`, after your movement code has set `body.velocity` for this frame:
## otherwise last frame's knockback is still in it and gets added again.
func velocity_with_knockback(delta: float) -> Vector3:
	var combined := body.velocity + _knockback
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_decay * delta * maxf(_knockback.length(), _MIN_DECAY_SPEED))
	return combined


## Returns whether a knockback is still moving the body.
func is_knocked_back() -> bool:
	return _knockback != Vector3.ZERO


## Returns the objects registered in `index` within `neighbor_radius` of the body —
## the body itself too, if it is registered. A fresh query each call.
func neighbors_in(index: LFSpatialIndex) -> Array:
	return index.query_radius(body.global_position, neighbor_radius)


## The one call per physics frame: separation and blocking, applied to `body.velocity`.
## The push is added to it, so set `body.velocity` afresh each frame before calling.
## Every `refresh_frames` calls the neighbors are asked of `index` again and the
## separation push recomputed; in between, the last push is reused and blocking runs
## against the last neighbor list (skipping any since freed), with the peers `peer_of`
## gave at that refresh (see `peer_of`).
func resolve(index: LFSpatialIndex) -> void:
	_frame += 1
	if _frame >= refresh_frames:
		_frame = 0
		_neighbors = neighbors_in(index)
		_push = separation_from(_neighbors)
		_collect_peers()
	body.velocity += _push
	_block_kept_peers()


## Makes the next `resolve` re-query the neighbors (after a teleport or a spawn, say).
func refresh_next() -> void:
	_frame = refresh_frames


## Adds `separation_from(neighbors)` to `body.velocity`: a symmetric push apart that
## ignores weight, so two equal bodies pressing together still separate. For custom
## loops; `resolve` already does this.
func resolve_separation(neighbors: Array) -> void:
	body.velocity += separation_from(neighbors)


## Returns the push (a velocity) away from every CharacterBody3D in `neighbors` closer
## than `separation_radius` on the ground plane, in proportion to the overlap. Changes
## nothing. An exactly overlapping neighbor pushes in a random direction. Freed
## neighbors, non-bodies and the body itself are skipped.
func separation_from(neighbors: Array) -> Vector3:
	var push := Vector3.ZERO
	for other: Variant in neighbors:
		if !is_instance_valid(other) or other == body or !(other is CharacterBody3D):
			continue
		var offset: Vector3 = body.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance >= separation_radius:
			continue
		var direction := offset / distance if distance >= _OVERLAP_EPSILON else LFUtils3D.random_direction_xz(rng)
		push += direction * (separation_radius - distance) * separation_strength
	return push


## Cancels the part of `body.velocity` heading into any heavier neighbor (on the ground
## plane), so a lighter body cannot push through a heavier one; a heavier body moves on
## unhindered. Wedged between heavier neighbors, it keeps only the movement that heads
## into none of them (none at all if no such way remains). Neighbors `peer_of` gives no
## crowd body for, freed ones and the body itself are skipped. Vertical velocity is left
## alone. For custom loops; `resolve` already does this.
func resolve_blocking(neighbors: Array) -> void:
	_blockers.clear()
	var own_position := body.global_position
	for other: Variant in neighbors:
		if !is_instance_valid(other) or other == body or !(other is CharacterBody3D):
			continue
		var peer: LFCrowdBody = peer_of.call(other)
		if peer == null or weight >= peer.weight:
			continue
		_add_blocker(other.global_position - own_position)
	_slide_past_blockers()


# Fills `_peer_bodies` and `_peer_ids` with the live CharacterBody3D neighbors other than
# the body that `peer_of` gives a crowd body for, and those crowd bodies' instance ids.
func _collect_peers() -> void:
	_peer_bodies.clear()
	_peer_ids.clear()
	for other: Variant in _neighbors:
		if !is_instance_valid(other) or other == body or !(other is CharacterBody3D):
			continue
		var peer: LFCrowdBody = peer_of.call(other)
		if peer != null:
			_peer_bodies.append(other)
			_peer_ids.append(peer.get_instance_id())


# `resolve_blocking` against the peers kept from the last refresh; a freed body is skipped.
func _block_kept_peers() -> void:
	_blockers.clear()
	var own_position := body.global_position
	for i in _peer_bodies.size():
		var other: Variant = _peer_bodies[i]
		if !is_instance_valid(other):
			continue
		var peer := instance_from_id(_peer_ids[i]) as LFCrowdBody
		if peer == null:
			# The crowd body `peer_of` gave is gone (one made just for its answer): ask again.
			peer = peer_of.call(other)
			if peer == null:
				continue
		if weight >= peer.weight:
			continue
		_add_blocker(other.global_position - own_position)
	_slide_past_blockers()


# Adds the ground-plane direction of `toward_other` to `_blockers`, unless the neighbor
# sits on the very spot (no direction to block).
func _add_blocker(toward_other: Vector3) -> void:
	toward_other.y = 0.0
	if toward_other.length() >= _OVERLAP_EPSILON:
		_blockers.append(toward_other.normalized())


# Changes `body.velocity` to the ground velocity closest to it that heads into none of
# `_blockers`; vertical velocity is kept.
func _slide_past_blockers() -> void:
	if _blockers.is_empty():
		return
	# The allowed ground velocities form a cone (no part toward any blocker); the result is
	# the allowed one closest to the current velocity: unchanged, slid along one blocker's
	# edge, or stopped.
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var best := Vector3.ZERO
	if _heads_into_none(flat, _blockers):
		best = flat
	else:
		for into in _blockers:
			var toward := flat.dot(into)
			if toward <= 0.0:
				continue
			var slid := flat - into * toward
			if _heads_into_none(slid, _blockers) and slid.distance_squared_to(flat) < best.distance_squared_to(flat):
				best = slid
	body.velocity = Vector3(best.x, body.velocity.y, best.z)


static func _heads_into_none(velocity: Vector3, blockers: Array[Vector3]) -> bool:
	for into in blockers:
		if velocity.dot(into) > _HEADING_EPSILON:
			return false
	return true
