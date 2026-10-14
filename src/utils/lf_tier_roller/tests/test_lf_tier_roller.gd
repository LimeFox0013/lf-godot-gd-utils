extends GutTest

const WEIGHTS := [60.0, 25.0, 10.0, 4.0, 1.0]


func _buckets(counts: Array) -> Array:
	var buckets := []
	for tier in counts.size():
		var bucket := []
		for i in counts[tier]:
			bucket.append('%d-%d' % [tier, i])
		buckets.append(bucket)
	return buckets


func test_the_tier_is_chosen_by_weight():
	var buckets := _buckets([1, 1, 1, 1, 1])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.0, 0.0), '0-0')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.61, 0.0), '1-0')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.86, 0.0), '2-0')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.96, 0.0), '3-0')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.995, 0.0), '4-0')


func test_the_floor_excludes_lower_tiers():
	var buckets := _buckets([1, 1, 1, 1, 1])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.0, 0.0, 2), '2-0')


func test_an_empty_tier_falls_lower_first_then_higher():
	var buckets := _buckets([1, 0, 0, 1, 0])
	assert_eq(LFTierRoller.resolve_tier(buckets, 2, 0), 0, 'lower first')
	assert_eq(LFTierRoller.resolve_tier(buckets, 2, 1), 3, 'not below the floor, then higher')
	assert_eq(LFTierRoller.resolve_tier(buckets, 2, 0, LFTierRoller.Fallback.HIGHER_FIRST), 3)
	assert_eq(LFTierRoller.resolve_tier(_buckets([0, 0, 0]), 1, 0), -1)


func test_with_nothing_at_or_above_the_floor_the_floor_is_dropped():
	var buckets := _buckets([2, 0, 0, 0, 0])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, WEIGHTS, 0.99, 0.0, 3), '0-0')


func test_no_items_returns_nothing_and_draws_nothing():
	var rng := LFRandom.new(1)
	var before := rng.state
	assert_null(LFTierRoller.pick([], _tier_of, WEIGHTS, rng))
	assert_eq(rng.state, before)


func _tier_of(item: String) -> int:
	return int(item.get_slice('-', 0))


func test_a_pick_draws_two_values_tier_first():
	var items := ['0-a', '1-b', '1-c', '3-d']
	for seed_value in 50:
		var rng := LFRandom.new(seed_value)
		var twin := LFRandom.new(seed_value)
		var tier_roll := twin.randf()
		var item_roll := twin.randf()
		var expected: Variant = LFTierRoller.pick_from_buckets(LFTierRoller.bucket(items, _tier_of, 5), WEIGHTS, tier_roll, item_roll)
		assert_eq(LFTierRoller.pick(items, _tier_of, WEIGHTS, rng), expected)
		assert_eq(rng.state, twin.state)


func test_items_are_picked_uniformly_within_a_tier():
	var buckets := _buckets([4])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0], 0.0, 0.0), '0-0')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0], 0.0, 0.26), '0-1')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0], 0.0, 0.99), '0-3')
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0], 0.0, 1.0), '0-3', 'a roll of 1 stays in range')


func test_an_out_of_range_tier_is_skipped():
	var buckets := LFTierRoller.bucket(['0-a', '9-b'], _tier_of, 3)
	assert_push_error('LFTierRoller')
	assert_eq(buckets, [['0-a'], [], []])


func test_zero_weights_from_the_floor_up_resolve_to_the_floor_tier():
	var buckets := _buckets([1, 1, 1])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [5.0, 0.0, 0.0], 0.5, 0.0, 1), '1-0')


func test_higher_first_with_nothing_higher_falls_back_down():
	var buckets := _buckets([1, 0, 0, 0])
	assert_eq(LFTierRoller.resolve_tier(buckets, 2, 0, LFTierRoller.Fallback.HIGHER_FIRST), 0)


func test_a_negative_floor_counts_as_zero():
	var buckets := _buckets([1, 1, 1])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0, 1.0, 1.0], 0.0, 0.0, -1), '0-0', 'never the last bucket through index -1')
	assert_eq(LFTierRoller.resolve_tier(_buckets([1, 0, 0]), 1, -2), 0)


func test_more_weights_than_buckets_never_index_past_the_last_bucket():
	var buckets := _buckets([1, 1])
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [1.0, 1.0, 1.0, 1.0], 0.99, 0.0), '1-0', 'a roll past the buckets lands on the last')
	assert_eq(LFTierRoller.resolve_tier(buckets, 7, 0), 1)
	assert_eq(LFTierRoller.resolve_tier([], 0, 0), -1)


func test_picking_without_a_generator_is_reported():
	assert_null(LFTierRoller.pick(['0-a'], _tier_of, [1.0], null))
	assert_push_error('generator')


func test_an_item_roll_of_one_stays_on_the_last_item():
	assert_eq(LFTierRoller.pick_from_buckets(_buckets([3]), [1.0], 0.0, 1.0), '0-2')


func test_lower_first_is_the_default_fallback():
	var buckets := _buckets([1, 0, 1])
	assert_eq(LFTierRoller.resolve_tier(buckets, 1, 0, LFTierRoller.Fallback.LOWER_FIRST), 0)
	assert_eq(LFTierRoller.resolve_tier(buckets, 1, 0), 0)
	assert_eq(LFTierRoller.pick_from_buckets(buckets, [0.0, 1.0, 0.0], 0.5, 0.0, 0, LFTierRoller.Fallback.HIGHER_FIRST), '2-0')


func test_every_bucket_empty_picks_nothing():
	assert_null(LFTierRoller.pick_from_buckets(_buckets([0, 0, 0]), [1.0, 1.0, 1.0], 0.5, 0.5))
	assert_null(LFTierRoller.pick_from_buckets([], [1.0], 0.5, 0.5))
	assert_null(LFTierRoller.pick_from_buckets([], [], 0.5, 0.5))


func test_a_floor_past_the_last_tier_is_dropped():
	assert_eq(LFTierRoller.pick_from_buckets(_buckets([1, 1]), [1.0, 1.0], 0.0, 0.0, 5), '0-0')


func test_pick_returns_nothing_when_every_item_is_out_of_range():
	assert_null(LFTierRoller.pick(['9-b'], _tier_of, WEIGHTS, LFRandom.new(1)))
	assert_push_error('LFTierRoller')


func test_pick_honours_the_floor_and_the_fallback():
	var items := ['0-a', '0-b', '2-c', '4-d']
	for seed_value in 30:
		assert_eq(_tier_of(LFTierRoller.pick(items, _tier_of, WEIGHTS, LFRandom.new(seed_value), 3)), 4, 'at least tier 3: only tier 4 is stocked')
	assert_eq(LFTierRoller.pick(['0-a', '2-b'], _tier_of, [0.0, 1.0, 0.0], LFRandom.new(1), 0, LFTierRoller.Fallback.HIGHER_FIRST), '2-b', 'tier 1 rolled, empty, upward first')


func test_bucket_keeps_the_original_order_within_a_tier():
	assert_eq(LFTierRoller.bucket(['1-x', '0-a', '1-y', '0-b'], _tier_of, 2), [['0-a', '0-b'], ['1-x', '1-y']])
	assert_eq(LFTierRoller.bucket([], _tier_of, 2), [[], []])


func test_a_rolled_tier_below_the_floor_with_items_is_kept_by_resolve_tier():
	# resolve_tier only applies the floor to the fallback search; pick_from_buckets never rolls below it.
	assert_eq(LFTierRoller.resolve_tier(_buckets([1, 0, 1]), 0, 2), 0)


func _reference_tilt(base: Array[float], luck: float, per_luck: float, floor_of_first: float) -> Array[float]:
	var max_shift := base[0] - floor_of_first
	var shift := clampf(maxf(luck, 0.0) * per_luck, 0.0, max_shift)
	var higher_total := 0.0
	for tier in range(1, base.size()):
		higher_total += base[tier]
	var weights: Array[float] = base.duplicate()
	weights[0] -= shift
	for tier in range(1, base.size()):
		weights[tier] += shift * base[tier] / higher_total
	return weights


func test_tilt_weights_match_the_plain_formula_bit_for_bit_over_many_values():
	var base: Array[float] = [50.0, 27.0, 15.0, 6.0, 2.0]
	var luck := -3.0
	while luck < 120.0:
		var shift := maxf(luck, 0.0) * 1.0
		assert_eq(LFTierRoller.tilt_weights(base, shift, 10.0), _reference_tilt(base, luck, 1.0, 10.0), 'luck %s' % luck)
		assert_eq(LFTierRoller.tilt_weights(base, maxf(luck, 0.0) * 0.37, 12.5), _reference_tilt(base, luck, 0.37, 12.5), 'scaled luck %s' % luck)
		luck += 0.37


func test_tilt_weights_moves_weight_in_proportion_and_respects_the_floor():
	var base: Array[float] = [50.0, 27.0, 15.0, 6.0, 2.0]
	var tilted := LFTierRoller.tilt_weights(base, 10.0, 10.0)
	var expected: Array[float] = [40.0, 32.4, 18.0, 7.2, 2.4]
	for tier in expected.size():
		assert_almost_eq(tilted[tier], expected[tier], 0.0001)
	assert_eq(LFTierRoller.tilt_weights(base, 1000.0, 10.0)[0], 10.0, 'the first tier stops at the floor')
	assert_eq(LFTierRoller.tilt_weights(base, -5.0, 10.0), base, 'a negative shift counts as 0')


func test_tilt_weights_returns_a_new_array_each_call():
	var base: Array[float] = [60.0, 40.0]
	var first := LFTierRoller.tilt_weights(base, 0.0, 0.0)
	first[0] = 1.0
	assert_eq(base, [60.0, 40.0] as Array[float], 'the base is untouched')
	assert_eq(LFTierRoller.tilt_weights(base, 0.0, 0.0), [60.0, 40.0] as Array[float])


func test_tilt_weights_leaves_degenerate_inputs_alone():
	assert_eq(LFTierRoller.tilt_weights([5.0], 3.0, 0.0), [5.0] as Array[float])
	assert_eq(LFTierRoller.tilt_weights([], 3.0, 0.0), [] as Array[float])
	assert_eq(LFTierRoller.tilt_weights([5.0, 0.0], 3.0, 0.0), [5.0, 0.0] as Array[float], 'nothing to spread over')
	assert_eq(LFTierRoller.tilt_weights([5.0, 5.0], 3.0, 9.0), [5.0, 5.0] as Array[float], 'a floor above the weight moves nothing')
