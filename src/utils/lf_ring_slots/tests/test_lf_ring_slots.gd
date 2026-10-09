extends GutTest

var spatial_index: LFSpatialIndex


func before_each():
	spatial_index = LFSpatialIndex.new(4.0)


func test_returns_the_waypoint_itself_when_nothing_occupies_it():
	var waypoint := Vector3(10, 0, 10)

	var slot := LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self')

	assert_eq(slot, waypoint)


func test_returns_a_nearby_free_position_when_the_waypoint_is_occupied():
	var waypoint := Vector3(10, 0, 10)
	spatial_index.register('occupant', waypoint)

	var slot := LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self')

	assert_ne(slot, waypoint, 'an occupied waypoint should redirect to a nearby free slot')
	assert_almost_eq(slot.distance_to(waypoint), LFRingSlots.DEFAULT_SPACING, 0.01, 'the first free ring should be exactly one slot-spacing out')


func test_ignores_the_agents_own_occupancy_at_the_waypoint():
	var waypoint := Vector3(10, 0, 10)
	spatial_index.register('self', waypoint)

	var slot := LFRingSlots.find_slot(waypoint, waypoint, spatial_index, 'self')

	assert_eq(slot, waypoint, 'an agent already standing on the waypoint should not be redirected away from its own spot')


func test_prefers_the_free_candidate_closest_to_the_approaching_unit():
	var waypoint := Vector3.ZERO
	spatial_index.register('occupant', waypoint)

	# Approaching from due +X — the nearest free ring position should be on that same
	# side, not an arbitrary one on the far side of the group.
	var slot := LFRingSlots.find_slot(waypoint, Vector3(5, 0, 0), spatial_index, 'self')

	assert_gt(slot.x, 0.0, 'the assigned slot should be on the side the agent is approaching from')


func test_degrades_to_the_outermost_ring_when_every_searched_ring_is_full():
	var waypoint := Vector3.ZERO
	var spacing := LFRingSlots.DEFAULT_SPACING
	var max_rings := 2
	spatial_index.register('center', waypoint)
	for ring in range(1, max_rings + 1):
		var radius := ring * spacing
		for pos in LFRingSlots.ring_candidates(waypoint, radius, spacing):
			spatial_index.register(str(pos), pos)

	var slot := LFRingSlots.find_slot(waypoint, Vector3(5, 0, 0), spatial_index, 'self', spacing, max_rings)

	assert_almost_eq(slot.distance_to(waypoint), max_rings * spacing, 0.01, 'with every searched ring full, the agent should degrade to the outermost ring rather than search forever')


func test_every_ring_mirrors_onto_itself_across_both_axes():
	var center := Vector3(10.0, 0.0, -4.0)
	for ring in range(1, LFRingSlots.DEFAULT_MAX_RINGS + 1):
		var candidates := LFRingSlots.ring_candidates(center, ring * 1.0, 1.0)
		for candidate in candidates:
			var mirrored_x := Vector3(2.0 * center.x - candidate.x, 0.0, candidate.z)
			var mirrored_z := Vector3(candidate.x, 0.0, 2.0 * center.z - candidate.z)
			assert_true(candidates.any(func(c): return c.distance_to(mirrored_x) < 0.001), 'ring %d mirrors across x' % ring)
			assert_true(candidates.any(func(c): return c.distance_to(mirrored_z) < 0.001), 'ring %d mirrors across z' % ring)


## Bodies stand with their origin above the ground point they occupy.
func test_an_occupant_standing_above_the_point_still_takes_it():
	var index := LFSpatialIndex.new(4.0, true)
	index.register('standing', Vector3(0, 0.5, 0))
	var slot := LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), index, 'self')
	assert_almost_eq(Vector2(slot.x, slot.z).length(), LFRingSlots.DEFAULT_SPACING, 0.01)


func test_an_occupant_on_another_level_leaves_the_point_free():
	var index := LFSpatialIndex.new(4.0, true)
	index.register('on the ridge', Vector3(0, 6.0, 0))
	assert_eq(LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), index, 'self'), Vector3.ZERO)


func test_a_non_positive_spacing_is_reported_and_answers_the_center():
	var index := LFSpatialIndex.new(4.0, true)
	index.register('a', Vector3.ZERO)
	assert_eq(LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), index, 'self', 0.0), Vector3.ZERO)
	assert_push_error('spacing')
	assert_eq(LFRingSlots.ring_candidates(Vector3.ZERO, 1.0, -1.0), [] as Array[Vector3])
	assert_push_error('spacing')


func test_a_non_finite_spacing_is_reported_and_answers_the_center():
	var index := LFSpatialIndex.new(4.0, true)
	for spacing: float in [INF, NAN]:
		assert_eq(LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), index, 'self', spacing), Vector3.ZERO)
		assert_push_error('spacing')
		assert_eq(LFRingSlots.ring_candidates(Vector3.ZERO, 1.0, spacing), [] as Array[Vector3])
		assert_push_error('spacing')


func test_an_arrival_from_nowhere_still_gets_a_slot():
	var index := LFSpatialIndex.new(4.0, true)
	index.register('a', Vector3.ZERO)
	var slot := LFRingSlots.find_slot(Vector3.ZERO, Vector3(NAN, 0, 0), index, 'self')
	assert_true(slot.is_finite())
	assert_almost_eq(slot.length(), LFRingSlots.DEFAULT_SPACING, 0.01)


func test_no_rings_answers_the_center_even_when_taken():
	var index := LFSpatialIndex.new(4.0, true)
	index.register('a', Vector3.ZERO)
	assert_eq(LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), index, 'self', 1.0, 0), Vector3.ZERO)


func test_the_candidate_count_depends_on_the_ring_not_the_scale():
	assert_eq(LFRingSlots.ring_candidates(Vector3.ZERO, 3.0, 1.0).size(), LFRingSlots.ring_candidates(Vector3.ZERO, 0.3, 0.1).size())


func test_a_fractional_ring_still_has_an_even_count_of_at_least_six():
	for radius in [0.4, 1.3, 2.7, 4.5]:
		var count := LFRingSlots.ring_candidates(Vector3.ZERO, radius, 1.0).size()
		assert_eq(count % 2, 0, 'radius %s' % radius)
		assert_gte(count, 6, 'radius %s' % radius)


func test_an_occupant_exactly_half_a_spacing_away_leaves_the_point_free():
	var waypoint := Vector3(10, 0, 10)
	spatial_index.register('beside', waypoint + Vector3(0.5, 0, 0))
	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self', 1.0), waypoint)


func test_an_occupant_exactly_one_spacing_above_leaves_the_point_free():
	var waypoint := Vector3(10, 0, 10)
	spatial_index.register('above', waypoint + Vector3(0, 1.0, 0))
	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self', 1.0), waypoint)


func test_rings_past_the_prebuilt_ones_still_answer():
	var waypoint := Vector3.ZERO
	spatial_index = LFSpatialIndex.new(1.0)
	for ring in range(0, 21):
		for point in LFRingSlots.ring_candidates(waypoint, float(ring), 1.0) if ring > 0 else [waypoint]:
			spatial_index.register(str(point), point)
	var slot := LFRingSlots.find_slot(waypoint, Vector3(100, 0, 0), spatial_index, 'self', 1.0, 22)
	assert_almost_eq(slot.distance_to(waypoint), 21.0, 0.01, 'rings 1-20 are full, so ring 21')


func test_an_arrival_has_no_slot_outside_the_enter_radius():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	assert_null(arrival.destination(Vector3.ZERO, Vector3(7, 0, 0), spatial_index, 'self'))
	assert_null(arrival.slot())


func test_an_arrival_claims_a_slot_inside_the_enter_radius():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	spatial_index.register('occupant', Vector3.ZERO)
	var slot: Variant = arrival.destination(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self')
	assert_not_null(slot)
	assert_almost_eq((slot as Vector3).distance_to(Vector3.ZERO), 1.0, 0.01)
	assert_eq(arrival.slot(), slot)


func test_a_held_slot_is_kept_out_to_the_exit_radius_and_never_re_searched():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	var slot: Variant = arrival.destination(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self')
	spatial_index.register('newcomer', slot)
	assert_eq(arrival.destination(Vector3.ZERO, Vector3(8, 0, 0), spatial_index, 'self'), slot, 'past enter, inside exit, taken since: kept')
	assert_null(arrival.destination(Vector3.ZERO, Vector3(9.5, 0, 0), spatial_index, 'self'), 'past exit')
	assert_null(arrival.destination(Vector3.ZERO, Vector3(8, 0, 0), spatial_index, 'self'), 'back inside exit but outside enter: none')


func test_extra_ok_false_drops_the_slot():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	arrival.destination(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self')
	assert_null(arrival.destination(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self', false))
	assert_null(arrival.slot())


func test_a_new_goal_or_reset_drops_the_slot():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	assert_eq(arrival.destination(Vector3.ZERO, Vector3(1, 0, 0), spatial_index, 'self'), Vector3.ZERO)
	assert_eq(arrival.destination(Vector3(2, 0, 0), Vector3(1, 0, 0), spatial_index, 'self'), Vector3(2, 0, 0), 'the new goal')
	arrival.reset()
	assert_null(arrival.slot())


func test_an_exit_radius_below_the_enter_radius_is_raised_to_it():
	var arrival := LFRingSlots.Arrival.new(6.0, 2.0)
	assert_eq(arrival.exit_radius, 6.0)


func test_occupants_of_another_key_type_than_exclude_are_compared_safely():
	var waypoint := Vector3(10, 0, 10)
	spatial_index.register(Vector3.ONE, waypoint)
	var slot := LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self')
	assert_almost_eq(slot.distance_to(waypoint), 1.0, 0.01, 'a Vector3 key is an occupant, not the String exclude')


func test_a_claimed_point_counts_as_taken_for_everyone_else():
	var waypoint := Vector3(10, 0, 10)
	var claims := LFRingSlots.Claims.new()
	claims.claim('first', waypoint)

	var slot := LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'second', LFRingSlots.DEFAULT_SPACING, LFRingSlots.DEFAULT_MAX_RINGS, claims)

	assert_almost_eq(slot.distance_to(waypoint), LFRingSlots.DEFAULT_SPACING, 0.01, 'the claimed centre is skipped')


func test_a_claim_never_blocks_its_own_claimant():
	var waypoint := Vector3(10, 0, 10)
	var claims := LFRingSlots.Claims.new()
	claims.claim('self', waypoint)

	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self', 1.0, 5, claims), waypoint)


func test_a_claim_on_another_level_leaves_the_point_free():
	var waypoint := Vector3(10, 0, 10)
	var claims := LFRingSlots.Claims.new()
	claims.claim('above', waypoint + Vector3(0, 3, 0))

	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self', 1.0, 5, claims), waypoint)


func test_claims_hold_one_slot_per_claimant_until_released():
	var claims := LFRingSlots.Claims.new()
	claims.claim('a', Vector3(1, 0, 0))
	claims.claim('a', Vector3(2, 0, 0))
	claims.claim('b', Vector3(3, 0, 0))

	assert_eq(claims.size(), 2, 'a claimant re-claiming moves its claim')
	assert_eq(claims.slot_of('a'), Vector3(2, 0, 0))
	claims.release('a')
	assert_null(claims.slot_of('a'))
	assert_eq(claims.size(), 1)
	claims.release('nobody')
	claims.clear()
	assert_eq(claims.size(), 0)


func test_a_freed_claimant_no_longer_holds_its_slot():
	var waypoint := Vector3(10, 0, 10)
	var claims := LFRingSlots.Claims.new()
	var claimant := Node.new()
	claims.claim(claimant, waypoint)
	claimant.free()

	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, spatial_index, 'self', 1.0, 5, claims), waypoint)
	assert_eq(claims.size(), 0, 'pruned on the next search')


func test_arrivals_sharing_claims_entering_together_take_different_slots():
	var goal := Vector3(10, 0, 0)
	var claims := LFRingSlots.Claims.new()
	var slots := []
	for i in 7:
		var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
		arrival.claims = claims
		slots.append(arrival.destination(goal, goal + Vector3(-5, 0, 0), spatial_index, 'agent%d' % i))

	for i in slots.size():
		for j in range(i + 1, slots.size()):
			assert_gt(slots[i].distance_to(slots[j]), 0.5, 'slots %d and %d differ' % [i, j])


func test_an_arrival_releases_its_claim_when_it_drops_the_slot():
	var goal := Vector3(10, 0, 0)
	var claims := LFRingSlots.Claims.new()
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	arrival.claims = claims
	arrival.destination(goal, goal, spatial_index, 'me')
	assert_eq(claims.slot_of('me'), goal)

	arrival.destination(goal, goal + Vector3(20, 0, 0), spatial_index, 'me')
	assert_null(claims.slot_of('me'), 'leaving the zone releases it')

	arrival.destination(goal, goal, spatial_index, 'me')
	arrival.reset()
	assert_null(claims.slot_of('me'), 'reset releases it')

	arrival.destination(goal, goal, spatial_index, 'me')
	arrival.destination(goal + Vector3(1, 0, 0), goal, spatial_index, 'me')
	assert_eq(claims.size(), 1, 'a new goal moves the claim, never leaves two')


func test_an_arrival_searches_with_its_own_spacing_and_rings():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0, 2.0, 1)
	assert_eq(arrival.spacing, 2.0)
	assert_eq(arrival.max_rings, 1)
	spatial_index.register('occupant', Vector3.ZERO)
	var slot: Variant = arrival.destination(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self')
	assert_almost_eq((slot as Vector3).length(), 2.0, 0.01, 'one ring, two units out')


func test_an_arrival_registered_under_null_still_releases_its_claim():
	var claims := LFRingSlots.Claims.new()
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	arrival.claims = claims
	arrival.destination(Vector3.ZERO, Vector3.ZERO, spatial_index, null)
	assert_eq(claims.size(), 1)
	arrival.reset()
	assert_eq(claims.size(), 0)


func test_an_arrival_releases_its_claim_from_the_claims_it_was_made_in():
	var first := LFRingSlots.Claims.new()
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	arrival.claims = first
	arrival.destination(Vector3.ZERO, Vector3.ZERO, spatial_index, 'me')
	arrival.claims = LFRingSlots.Claims.new()
	arrival.reset()
	assert_eq(first.size(), 0, 'swapping claims never strands the old claim')


func test_without_a_spatial_index_only_claims_take_spots():
	var waypoint := Vector3(10, 0, 10)
	assert_eq(LFRingSlots.find_slot(waypoint, Vector3.ZERO, null, 'self'), waypoint)
	var claims := LFRingSlots.Claims.new()
	claims.claim('other', waypoint)
	var slot := LFRingSlots.find_slot(waypoint, Vector3.ZERO, null, 'self', 1.0, 5, claims)
	assert_almost_eq(slot.distance_to(waypoint), 1.0, 0.01)


func test_with_every_ring_full_an_arrival_from_the_center_falls_back_along_plus_x():
	var waypoint := Vector3(3, 0, 3)
	spatial_index.register('center', waypoint)
	for pos in LFRingSlots.ring_candidates(waypoint, 1.0, 1.0):
		spatial_index.register(str(pos), pos)
	var slot := LFRingSlots.find_slot(waypoint, waypoint, spatial_index, 'self', 1.0, 1)
	assert_almost_eq(slot.distance_to(waypoint + Vector3(1, 0, 0)), 0.0, 0.001, 'no direction to keep: +X')


func test_the_fallback_point_faces_the_arrival():
	var waypoint := Vector3.ZERO
	spatial_index.register('center', waypoint)
	for pos in LFRingSlots.ring_candidates(waypoint, 1.0, 1.0):
		spatial_index.register(str(pos), pos)
	var slot := LFRingSlots.find_slot(waypoint, Vector3(0, 0, -7), spatial_index, 'self', 1.0, 1)
	assert_almost_eq(slot.distance_to(Vector3(0, 0, -1)), 0.0, 0.001)


func test_a_negative_ring_count_searches_no_rings():
	spatial_index.register('a', Vector3.ZERO)
	assert_eq(LFRingSlots.find_slot(Vector3.ZERO, Vector3(5, 0, 0), spatial_index, 'self', 1.0, -2), Vector3.ZERO)


func test_a_slot_keeps_the_height_of_the_point():
	var waypoint := Vector3(0, 2.5, 0)
	var index := LFSpatialIndex.new(4.0, true)
	index.register('a', waypoint)
	var slot := LFRingSlots.find_slot(waypoint, Vector3(5, 2.5, 0), index, 'self')
	assert_eq(slot.y, 2.5)


func test_ring_candidates_lie_on_the_ring_at_the_points_height():
	var center := Vector3(1, 4, -2)
	var candidates := LFRingSlots.ring_candidates(center, 2.0, 1.0)
	assert_eq(candidates.size(), 12)
	for candidate in candidates:
		assert_almost_eq(Vector2(candidate.x - center.x, candidate.z - center.z).length(), 2.0, 0.0001)
		assert_eq(candidate.y, center.y)


func test_an_arrival_from_a_non_finite_position_gets_no_slot():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	assert_null(arrival.destination(Vector3.ZERO, Vector3(NAN, 0, 0), spatial_index, 'self'))


func test_an_arrival_without_claims_claims_nothing():
	var arrival := LFRingSlots.Arrival.new(6.0, 9.0)
	var slot: Variant = arrival.destination(Vector3.ZERO, Vector3(1, 0, 0), spatial_index, 'self')
	assert_eq(slot, Vector3.ZERO)
	assert_null(arrival.claims)
