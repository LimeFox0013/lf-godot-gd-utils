extends GutTest

var index: LFSpatialIndex


func before_each():
	index = LFSpatialIndex.new(5.0, true)


## A sphere body of radius 0.5 that collides with the ground and obstacles (layers 1 and 3)
## but not with other crowd bodies (layer 2), registered in `index`.
func _body(position: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 5
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	body.add_child(shape)
	body.position = position
	add_child_autofree(body)
	index.register(body, position)
	return body


## Moves `body` by its velocity and keeps its index entry current, as a crowd's movement does.
func _slide(body: CharacterBody3D) -> void:
	body.move_and_slide()
	index.update_position(body, body.global_position)


func test_knockback_moves_the_body_on_its_own_and_dies_out():
	var body := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(body, 1.0)
	body.velocity = Vector3.ZERO

	crowd.apply_knockback(Vector3.RIGHT, 10.0)
	assert_true(crowd.is_knocked_back())
	var first := crowd.velocity_with_knockback(0.016)
	assert_gt(first.x, 0.0, 'knockback moves the body with no velocity of its own')

	var last := first
	for i in 200:
		last = crowd.velocity_with_knockback(0.016)
	assert_almost_eq(last.x, 0.0, 0.05, 'and dies out over time')


func test_knockback_decay_is_tunable():
	var slow := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	var fast := LFCrowdBody.new(_body(Vector3(10, 0, 0)), 1.0)
	fast.knockback_decay = 30.0
	slow.apply_knockback(Vector3.RIGHT, 10.0)
	fast.apply_knockback(Vector3.RIGHT, 10.0)
	for i in 10:
		slow.velocity_with_knockback(0.016)
		fast.velocity_with_knockback(0.016)
	assert_gt(slow.velocity_with_knockback(0.016).x, fast.velocity_with_knockback(0.016).x)


func test_a_lighter_body_cannot_pass_through_a_heavier_one():
	var heavy := _body(Vector3(1.0, 0, 0))
	LFCrowdBody.new(heavy, 10.0)
	var light := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(light, 1.0)

	for i in 60:
		await get_tree().physics_frame
		light.velocity = Vector3(2.0, 0, 0)
		crowd.resolve_blocking(crowd.neighbors_in(index))
		_slide(light)

	assert_lt(light.position.x, heavy.position.x, 'a lighter body never reaches or passes a heavier one')


func test_a_heavier_body_is_not_blocked_by_a_lighter_one():
	var light := _body(Vector3(1.0, 0, 0))
	LFCrowdBody.new(light, 1.0)
	var heavy := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(heavy, 10.0)

	var start_x := heavy.position.x
	for i in 60:
		await get_tree().physics_frame
		heavy.velocity = Vector3(2.0, 0, 0)
		crowd.resolve_blocking(crowd.neighbors_in(index))
		_slide(heavy)

	assert_almost_eq(heavy.position.x, start_x + 2.0, 0.05, 'a second at 2 units per second, through the lighter body')


func test_a_neighbor_without_a_crowd_body_never_blocks():
	var stranger := _body(Vector3(1.0, 0, 0))
	stranger.remove_meta(LFCrowdBody.META)
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.body.velocity = Vector3(2, 0, 0)
	crowd.resolve_blocking([stranger])
	assert_eq(crowd.body.velocity, Vector3(2, 0, 0))


func test_peer_of_can_be_injected():
	var heavy := _body(Vector3(1.0, 0, 0))
	var heavy_crowd := LFCrowdBody.new(null, 10.0)
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.peer_of = func(other): return heavy_crowd if other == heavy else null
	crowd.body.velocity = Vector3(2, 0, 0)
	crowd.resolve_blocking([heavy])
	assert_almost_eq(crowd.body.velocity.x, 0.0, 0.0001, 'blocked by the injected heavier peer')


func test_a_crowd_body_registers_itself_on_its_body():
	var body := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(body, 2.0)
	assert_eq(LFCrowdBody.of(body), crowd)
	assert_null(LFCrowdBody.of(_body(Vector3.ONE)), 'none registered')
	assert_null(LFCrowdBody.of(null))


func test_equal_weight_bodies_pressed_together_push_apart():
	var a := _body(Vector3(0.1, 0, 0))
	var a_crowd := LFCrowdBody.new(a, 1.0)
	var b := _body(Vector3(-0.1, 0, 0))
	var b_crowd := LFCrowdBody.new(b, 1.0)

	# Neither is heavier, so blocking alone does nothing — only separation pushes them apart.
	for i in 30:
		await get_tree().physics_frame
		a.velocity = Vector3.ZERO
		b.velocity = Vector3.ZERO
		a_crowd.resolve_separation(a_crowd.neighbors_in(index))
		b_crowd.resolve_separation(b_crowd.neighbors_in(index))
		_slide(a)
		_slide(b)

	assert_gt(a.position.distance_to(b.position), 0.2)


func test_exactly_overlapping_bodies_still_push_apart():
	var a := _body(Vector3.ZERO)
	var a_crowd := LFCrowdBody.new(a, 1.0, LFRandom.new(1))
	var b := _body(Vector3.ZERO)
	var b_crowd := LFCrowdBody.new(b, 1.0, LFRandom.new(2))

	for i in 30:
		await get_tree().physics_frame
		a.velocity = Vector3.ZERO
		b.velocity = Vector3.ZERO
		a_crowd.resolve_separation(a_crowd.neighbors_in(index))
		b_crowd.resolve_separation(b_crowd.neighbors_in(index))
		_slide(a)
		_slide(b)

	assert_gt(a.position.distance_to(b.position), 0.0, 'bodies spawned on top of each other separate')


func test_the_tie_break_direction_comes_from_the_generator():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3.ZERO)
	var one := LFCrowdBody.new(a, 1.0, LFRandom.new(5))
	var twin := LFCrowdBody.new(a, 1.0, LFRandom.new(5))
	assert_eq(one.separation_from([b]), twin.separation_from([b]), 'same seed, same push')
	var other := LFCrowdBody.new(a, 1.0, LFRandom.new(6))
	assert_ne(other.separation_from([b]), one.separation_from([b]), 'another seed, another direction')


func test_separation_stops_at_its_radius():
	var a := _body(Vector3(5.0, 0, 0))
	LFCrowdBody.new(a, 1.0)
	var b := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(b, 1.0)
	crowd.resolve_separation(crowd.neighbors_in(index))
	assert_eq(b.velocity, Vector3.ZERO, 'bodies far apart are not pushed')


func test_separation_radius_and_strength_are_tunable():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(1.5, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	assert_eq(crowd.separation_from([b]), Vector3.ZERO, 'beyond the default radius')
	crowd.separation_radius = 2.0
	var push := crowd.separation_from([b])
	assert_almost_eq(push.x, -(2.0 - 1.5) * 3.0, 0.0001)
	crowd.separation_strength = 6.0
	assert_almost_eq(crowd.separation_from([b]).x, -(2.0 - 1.5) * 6.0, 0.0001)


func test_neighbors_are_the_indexed_bodies_within_touching_distance():
	var a := _body(Vector3.ZERO)
	var touching := _body(Vector3(0.9, 0, 0))
	var apart := _body(Vector3(1.5, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)

	var neighbors := crowd.neighbors_in(index)

	assert_true(neighbors.has(touching))
	assert_false(neighbors.has(apart), 'beyond neighbor_radius')
	crowd.neighbor_radius = 2.0
	assert_true(crowd.neighbors_in(index).has(apart))


func test_the_body_itself_and_freed_neighbors_are_skipped():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.3, 0, 0))
	LFCrowdBody.new(b, 10.0)
	var crowd := LFCrowdBody.new(a, 1.0)
	var neighbors := crowd.neighbors_in(index)
	b.free()

	a.velocity = Vector3(2, 0, 0)
	crowd.resolve_separation(neighbors)
	crowd.resolve_blocking(neighbors)

	assert_eq(a.velocity, Vector3(2, 0, 0), 'nothing left to push or block against')


func test_the_crowd_push_is_worked_out_every_few_frames_and_reused_in_between():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.3, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	LFCrowdBody.new(b, 1.0)
	crowd.refresh_next()

	a.velocity = Vector3.ZERO
	crowd.resolve(index)
	var push := a.velocity
	assert_lt(push.x, 0.0, 'pushed away from the overlapping neighbor')

	b.position = Vector3(50, 0, 0) # moved far away, but not re-queried yet
	index.update_position(b, b.position)
	a.velocity = Vector3.ZERO
	crowd.resolve(index)
	assert_almost_eq(a.velocity.x, push.x, 0.0001, 'the last push is reused until the next refresh')

	for i in crowd.refresh_frames:
		a.velocity = Vector3.ZERO
		crowd.resolve(index)
	assert_eq(a.velocity, Vector3.ZERO, 'refreshed: nobody near any more')


func test_refresh_frames_is_at_least_one():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.refresh_frames = 0
	assert_eq(crowd.refresh_frames, 1)


func test_a_refresh_frames_of_one_queries_every_call():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.3, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	crowd.refresh_frames = 1
	crowd.resolve(index)
	b.position = Vector3(50, 0, 0)
	index.update_position(b, b.position)
	a.velocity = Vector3.ZERO
	crowd.resolve(index)
	assert_eq(a.velocity, Vector3.ZERO)


func test_a_neighbor_freed_between_refreshes_is_skipped():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.3, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	LFCrowdBody.new(b, 10.0)
	crowd.refresh_next()
	crowd.resolve(index)

	b.free()
	a.velocity = Vector3(2, 0, 0)
	crowd.resolve(index)

	assert_almost_eq(a.velocity.x, 2.0 - (0.9 - 0.3) * 3.0, 0.0001, 'own velocity plus the reused push: the freed heavy neighbor blocks nothing')


func test_a_lighter_body_wedged_between_two_heavier_ones_heads_into_neither():
	var light := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(light, 1.0)
	var left := _body(Vector3(-0.8, 0, 0.6))
	var right := _body(Vector3(0.8, 0, 0.6))
	LFCrowdBody.new(left, 10.0)
	LFCrowdBody.new(right, 10.0)

	light.velocity = Vector3(0, -1, 2)
	crowd.resolve_blocking([left, right])

	assert_lte(light.velocity.dot(Vector3(-0.8, 0, 0.6)), 0.0001, 'not into the left one')
	assert_lte(light.velocity.dot(Vector3(0.8, 0, 0.6)), 0.0001, 'not into the right one')
	assert_eq(light.velocity.y, -1.0, 'vertical velocity is left alone')


func test_blocking_keeps_the_part_of_the_velocity_heading_into_no_heavier_body():
	var light := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(light, 1.0)
	var ahead := _body(Vector3(0, 0, 0.8))
	var beside := _body(Vector3(0.8, 0, 0))
	LFCrowdBody.new(ahead, 10.0)
	LFCrowdBody.new(beside, 10.0)

	light.velocity = Vector3(-1, 0, 1)
	crowd.resolve_blocking([ahead, beside])

	assert_almost_eq(light.velocity, Vector3(-1, 0, 0), Vector3.ONE * 0.0001, 'slides along the body ahead, away from the one beside')


func test_of_a_freed_or_non_object_value_is_null():
	var body := CharacterBody3D.new()
	LFCrowdBody.new(body)
	body.free()
	assert_null(LFCrowdBody.of(body))
	assert_null(LFCrowdBody.of(42))


func test_a_decay_of_6_loses_a_tenth_of_the_knockback_per_frame_at_60_fps():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.apply_knockback(Vector3.RIGHT, 10.0)
	crowd.velocity_with_knockback(1.0 / 60.0)
	assert_almost_eq(crowd.velocity_with_knockback(1.0 / 60.0).x, 9.0, 0.0001)


func test_a_frame_longer_than_the_decay_ends_the_knockback():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.apply_knockback(Vector3.RIGHT, 10.0)
	crowd.velocity_with_knockback(1.0)
	assert_false(crowd.is_knocked_back())


func test_a_zero_direction_cancels_the_knockback():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.apply_knockback(Vector3.RIGHT, 10.0)
	crowd.apply_knockback(Vector3.ZERO, 10.0)
	assert_false(crowd.is_knocked_back())


func test_a_new_crowd_body_starts_with_the_documented_defaults():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO))
	assert_eq(crowd.weight, LFCrowdBody.DEFAULT_WEIGHT)
	assert_eq(crowd.knockback_decay, 6.0)
	assert_eq(crowd.separation_radius, 0.9)
	assert_eq(crowd.separation_strength, 3.0)
	assert_eq(crowd.neighbor_radius, 1.0)
	assert_eq(crowd.refresh_frames, 3)
	assert_null(crowd.rng)
	assert_false(crowd.is_knocked_back())


func test_a_body_less_peer_has_no_body_and_keeps_its_weight():
	var peer := LFCrowdBody.new(null, 4.0)
	assert_null(peer.body)
	assert_eq(peer.weight, 4.0)


func test_knockback_adds_to_the_bodys_own_velocity():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.body.velocity = Vector3(0, -2, 3)
	crowd.apply_knockback(Vector3(5, 0, 0), 4.0)
	assert_almost_eq(crowd.velocity_with_knockback(0.0), Vector3(4, -2, 3), Vector3.ONE * 0.0001, 'own velocity plus a knockback of speed 4 (direction normalized)')


func test_a_new_knockback_replaces_the_running_one():
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.body.velocity = Vector3.ZERO
	crowd.apply_knockback(Vector3.RIGHT, 10.0)
	crowd.apply_knockback(Vector3.BACK, 2.0)
	assert_almost_eq(crowd.velocity_with_knockback(0.0), Vector3(0, 0, 2), Vector3.ONE * 0.0001)


func test_the_first_refresh_comes_within_refresh_frames_calls_without_refresh_next():
	var a := _body(Vector3.ZERO)
	_body(Vector3(0.3, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0, LFRandom.new(3))
	var pushed := false
	for i in crowd.refresh_frames:
		a.velocity = Vector3.ZERO
		crowd.resolve(index)
		pushed = pushed or a.velocity.x < 0.0
	assert_true(pushed, 'the staggered first query lands inside the first refresh_frames calls')


func test_separation_and_blocking_skip_neighbors_that_are_not_bodies():
	var a := _body(Vector3.ZERO)
	var crowd := LFCrowdBody.new(a, 1.0)
	var marker := Node3D.new()
	marker.position = Vector3(0.3, 0, 0)
	add_child_autofree(marker)
	crowd.peer_of = func(_other): return LFCrowdBody.new(null, 10.0)
	assert_eq(crowd.separation_from([marker]), Vector3.ZERO)
	a.velocity = Vector3(2, 0, 0)
	crowd.resolve_blocking([marker])
	assert_eq(a.velocity, Vector3(2, 0, 0))


func test_separation_measures_overlap_on_the_ground_plane():
	var a := _body(Vector3.ZERO)
	var above := _body(Vector3(0.3, 5.0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	var push := crowd.separation_from([above])
	assert_almost_eq(push, Vector3(-(0.9 - 0.3) * 3.0, 0, 0), Vector3.ONE * 0.0001, 'height is ignored and the push is flat')


func test_an_equal_weight_neighbor_never_blocks():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.8, 0, 0))
	var crowd := LFCrowdBody.new(a, 2.0)
	LFCrowdBody.new(b, 2.0)
	a.velocity = Vector3(2, 0, 0)
	crowd.resolve_blocking([b])
	assert_eq(a.velocity, Vector3(2, 0, 0))


func test_moving_away_from_a_heavier_neighbor_is_unhindered():
	var a := _body(Vector3.ZERO)
	var heavy := _body(Vector3(0.8, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	LFCrowdBody.new(heavy, 10.0)
	a.velocity = Vector3(-2, 0, 1)
	crowd.resolve_blocking([heavy])
	assert_eq(a.velocity, Vector3(-2, 0, 1))


func test_a_heavier_neighbor_exactly_on_the_spot_gives_no_direction_to_block():
	var a := _body(Vector3.ZERO)
	var heavy := _body(Vector3(0, 2.0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	LFCrowdBody.new(heavy, 10.0)
	a.velocity = Vector3(2, 0, 0)
	crowd.resolve_blocking([heavy])
	assert_eq(a.velocity, Vector3(2, 0, 0), 'straight above on the ground plane: no blocking direction')


func test_a_lighter_body_heading_straight_into_a_heavier_one_stops_but_keeps_its_fall():
	var a := _body(Vector3.ZERO)
	var heavy := _body(Vector3(0.8, 0, 0))
	var crowd := LFCrowdBody.new(a, 1.0)
	LFCrowdBody.new(heavy, 10.0)
	a.velocity = Vector3(2, -3, 0)
	crowd.resolve_blocking([heavy])
	assert_almost_eq(a.velocity, Vector3(0, -3, 0), Vector3.ONE * 0.0001)


## Two copies of one crowd of mixed weights, run frame by frame: one through `resolve`
## (peers kept from each refresh), the other through what it stands for written out in
## full — a refresh every `refresh_frames` calls, the reused push, and blocking that asks
## `peer_of` about every neighbor every call (`_reference_blocking`). Every velocity
## matches on every frame.
func test_resolve_matches_separation_plus_blocking_on_a_moving_crowd():
	var worlds: Array = []
	var indexes: Array[LFSpatialIndex] = []
	for copy in 2:
		index = LFSpatialIndex.new(5.0, true)  # each copy in an index of its own
		indexes.append(index)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var crowd: Array[LFCrowdBody] = []
		for i in 40:
			var body := _body(Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)))
			crowd.append(LFCrowdBody.new(body, [0.5, 1.0, 2.0][i % 3], rng))
		worlds.append(crowd)
	var direct: Array[LFCrowdBody] = worlds[0]
	var pieces: Array[LFCrowdBody] = worlds[1]
	var frames: Array[int] = []
	var pushes: Array[Vector3] = []
	for crowd in pieces:
		frames.append(crowd._frame)
		pushes.append(Vector3.ZERO)
	var neighbors: Array = []
	neighbors.resize(pieces.size())
	neighbors.fill([])
	for frame in 12:
		for i in direct.size():
			var heading := Vector3(sin(frame + i), 0, cos(frame * 0.5 + i)) * 2.0
			direct[i].body.velocity = heading
			direct[i].resolve(indexes[0])
			pieces[i].body.velocity = heading
			frames[i] += 1
			if frames[i] >= pieces[i].refresh_frames:
				frames[i] = 0
				neighbors[i] = pieces[i].neighbors_in(indexes[1])
				pushes[i] = pieces[i].separation_from(neighbors[i])
			pieces[i].body.velocity += pushes[i]
			_reference_blocking(pieces[i], neighbors[i])
			assert_eq(direct[i].body.velocity, pieces[i].body.velocity, 'frame %d, body %d' % [frame, i])
		for copy in 2:
			for crowd: LFCrowdBody in worlds[copy]:
				crowd.body.position += crowd.body.velocity / 60.0
				indexes[copy].update_position(crowd.body, crowd.body.position)


## Blocking written out on its own, asking `peer_of` every call: what `resolve` must
## still give with the peers it keeps between refreshes.
func _reference_blocking(crowd: LFCrowdBody, neighbors: Array) -> void:
	var blockers: Array[Vector3] = []
	for other in neighbors:
		if !is_instance_valid(other) or other == crowd.body or !(other is CharacterBody3D):
			continue
		var peer: LFCrowdBody = crowd.peer_of.call(other)
		if peer == null or crowd.weight >= peer.weight:
			continue
		var toward_other: Vector3 = other.global_position - crowd.body.global_position
		toward_other.y = 0.0
		if toward_other.length() >= 0.001:
			blockers.append(toward_other.normalized())
	if blockers.is_empty():
		return
	var heads_into_none := func(velocity: Vector3) -> bool:
		for into in blockers:
			if velocity.dot(into) > 0.00001:
				return false
		return true
	var flat := Vector3(crowd.body.velocity.x, 0.0, crowd.body.velocity.z)
	var best := Vector3.ZERO
	if heads_into_none.call(flat):
		best = flat
	else:
		for into in blockers:
			var toward := flat.dot(into)
			if toward <= 0.0:
				continue
			var slid := flat - into * toward
			if heads_into_none.call(slid) and slid.distance_squared_to(flat) < best.distance_squared_to(flat):
				best = slid
	crowd.body.velocity = Vector3(best.x, crowd.body.velocity.y, best.z)


## `resolve` asks `peer_of` about each neighbor once per refresh, not every call, while a
## peer's weight still counts as it is now.
func test_resolve_asks_peer_of_only_at_a_refresh_and_reads_weights_live():
	var light := _body(Vector3.ZERO)
	var other := _body(Vector3(1.0, 0, 0))
	var other_crowd := LFCrowdBody.new(other, 0.5)
	var crowd := LFCrowdBody.new(light, 1.0)
	var asked := [0]
	crowd.peer_of = func(node):
		asked[0] += 1
		return LFCrowdBody.of(node)
	crowd.refresh_frames = 4
	crowd.refresh_next()
	for i in 4:
		light.velocity = Vector3(2, 0, 0)
		crowd.resolve(index)
	assert_eq(asked[0], 1, 'one neighbor, one refresh')
	assert_eq(light.velocity, Vector3(2, 0, 0) + crowd._push, 'lighter neighbor: not blocked')
	other_crowd.weight = 10.0
	light.velocity = Vector3(2, 0, 0)
	crowd.resolve(index)
	assert_eq(asked[0], 2, 'the next refresh asks again')
	other_crowd.weight = 0.5
	light.velocity = Vector3(2, 0, 0)
	crowd.resolve(index)
	assert_eq(asked[0], 2, 'not between refreshes')
	assert_gt(light.velocity.x, 0.0, 'the weight drop counts at once')
	other_crowd.weight = 10.0
	light.velocity = Vector3(2, 0, 0)
	crowd.resolve(index)
	assert_almost_eq(light.velocity.x, 0.0, 0.0001, 'and so does a rise: blocked')


## Neighboring crowd bodies keep no reference to each other between refreshes: once
## their bodies are freed, both crowd bodies are freed too.
func test_neighboring_crowd_bodies_are_freed_with_their_bodies():
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3(0.5, 0, 0))
	var crowd_a := LFCrowdBody.new(a, 1.0)
	var crowd_b := LFCrowdBody.new(b, 2.0)
	crowd_a.refresh_next()
	crowd_b.refresh_next()
	crowd_a.resolve(index)
	crowd_b.resolve(index)
	var weak_a: WeakRef = weakref(crowd_a)
	var weak_b: WeakRef = weakref(crowd_b)
	crowd_a = null
	crowd_b = null
	index.clear()
	a.free()
	b.free()
	assert_null(weak_a.get_ref(), 'no cycle keeps the first alive')
	assert_null(weak_b.get_ref(), 'no cycle keeps the second alive')


## A `peer_of` that makes a crowd body just for its answer still blocks on every call
## between refreshes, as it does through `resolve_blocking`.
func test_a_peer_made_by_peer_of_on_the_fly_blocks_between_refreshes():
	var heavy := _body(Vector3(1.0, 0, 0))
	heavy.remove_meta(LFCrowdBody.META)
	var crowd := LFCrowdBody.new(_body(Vector3.ZERO), 1.0)
	crowd.peer_of = func(other): return LFCrowdBody.new(null, 10.0) if other == heavy else null
	crowd.refresh_frames = 3
	crowd.refresh_next()
	for i in 3:
		crowd.body.velocity = Vector3(2, 0, 0)
		crowd.resolve(index)
		assert_lte(crowd.body.velocity.x, 0.0, 'call %d: blocked' % i)
