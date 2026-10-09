extends GutTest

func test_a_roll_lands_in_the_index_whose_share_of_the_total_covers_it():
	var weights := [1.0, 3.0]

	assert_eq(LFWeightedPick.index(weights, 0.0), 0)
	assert_eq(LFWeightedPick.index(weights, 0.24), 0)
	assert_eq(LFWeightedPick.index(weights, 0.26), 1)


func test_indices_before_from_are_never_picked_and_the_rest_share_the_roll():
	var weights := [100.0, 1.0, 1.0]

	assert_eq(LFWeightedPick.index(weights, 0.0, 1), 1)
	assert_eq(LFWeightedPick.index(weights, 0.6, 1), 2)


func test_a_roll_of_one_or_more_picks_the_last_positive_weight():
	assert_eq(LFWeightedPick.index([1.0, 1.0], 1.0), 1)
	assert_eq(LFWeightedPick.index([1.0, -5.0], 1.0), 0, 'never the trailing negative weight')
	assert_eq(LFWeightedPick.index([1.0, 0.0], 1.0), 0, 'never the trailing zero weight')
	assert_eq(LFWeightedPick.index([1.0, 2.0], 7.0), 1)


func test_a_roll_at_or_below_zero_picks_the_first_positive_weight():
	assert_eq(LFWeightedPick.index([-5.0, 1.0], -0.1), 1)
	assert_eq(LFWeightedPick.index([0.0, 2.0, 1.0], 0.0), 1)


func test_a_nan_roll_picks_the_last_positive_weight():
	assert_eq(LFWeightedPick.index([1.0, 1.0, 0.0], NAN), 1)


func test_no_positive_weight_picks_nothing():
	assert_eq(LFWeightedPick.index([0.0, 0.0, 0.0], 0.5), -1)
	assert_eq(LFWeightedPick.index([-1.0, -1.0], 0.5), -1)


func test_a_start_past_the_end_or_no_weights_picks_nothing():
	assert_eq(LFWeightedPick.index([1.0, 1.0], 0.5, 2), -1)
	assert_eq(LFWeightedPick.index([1.0, 1.0], 0.5, 5), -1)
	assert_eq(LFWeightedPick.index([], 0.5), -1)


func test_negative_weights_count_as_zero():
	assert_eq(LFWeightedPick.index([-5.0, 1.0], 0.0), 1, 'a negative weight is never picked')
	assert_eq(LFWeightedPick.index([1.0, -1.0, 1.0], 0.75), 2, 'nor does it shrink the total')


func test_an_all_zero_tail_after_from_picks_nothing():
	assert_eq(LFWeightedPick.index([5.0, 0.0, 0.0], 0.3, 1), -1)


func test_a_negative_from_counts_from_the_start():
	assert_eq(LFWeightedPick.index([1.0, 1.0], 0.0, -3), 0)


func test_int_weights_are_read_as_numbers():
	assert_eq(LFWeightedPick.index([1, 3], 0.5), 1)


func test_index_by_agrees_with_index_for_every_rule():
	var cases := [
		[[1.0, 3.0], 0], [[100.0, 1.0, 1.0], 1], [[1.0, -5.0], 0], [[0.0, 0.0], 0],
		[[], 0], [[2, 1, 1], 0], [[1.0, 2.0], 5], [[1.0, 2.0], -3], [[0.0, 1.0, 0.0, 2.0, 0.0], 0],
	]
	for case in cases:
		var weights: Array = case[0]
		var weight_at := func(i: int) -> float: return weights[i]
		for roll in [-1.0, 0.0, 0.1, 0.33, 0.5, 0.75, 0.999, 1.0, 2.0, NAN]:
			assert_eq(LFWeightedPick.index_by(weights.size(), weight_at, roll, case[1]), LFWeightedPick.index(weights, roll, case[1]), '%s from %s, roll %s' % [weights, case[1], roll])


func test_index_by_reads_weights_through_the_callable():
	var shares := {0: 1.0, 1: 0.0, 2: 3.0}
	var share_of := func(i: int) -> float: return shares[i]
	assert_eq(LFWeightedPick.index_by(3, share_of, 0.2), 0)
	assert_eq(LFWeightedPick.index_by(3, share_of, 0.3), 2)
	assert_eq(LFWeightedPick.index_by(0, share_of, 0.3), -1, 'a count of 0 picks nothing')


func test_a_nan_weight_counts_as_zero():
	assert_eq(LFWeightedPick.index([NAN, 1.0], 0.0), 1)
	assert_eq(LFWeightedPick.index([1.0, NAN, 1.0], 0.75), 2, 'nor does it change the total')


func test_an_infinite_weight_counts_as_zero():
	assert_eq(LFWeightedPick.index([1.0, INF], 0.5), 0, 'never chosen, even as the last weight')
	assert_eq(LFWeightedPick.index([1.0, INF, 1.0], 0.75), 2, 'nor does it change the total')
	assert_eq(LFWeightedPick.index([INF], 0.5), -1, 'alone it leaves nothing to pick')
	var shares := [1.0, INF, 1.0]
	var share_of := func(i: int) -> float: return shares[i]
	assert_eq(LFWeightedPick.index_by(3, share_of, 0.75), 2, 'index_by follows the same rule')


func test_finite_weights_whose_total_overflows_still_pick_by_share():
	var huge := [1e308, 1e308, 1e308] # each finite, their total is past the float range
	assert_eq(LFWeightedPick.index(huge, 0.0), 0)
	assert_eq(LFWeightedPick.index(huge, 0.3), 0)
	assert_eq(LFWeightedPick.index(huge, 0.5), 1)
	assert_eq(LFWeightedPick.index(huge, 0.9), 2)
	assert_eq(LFWeightedPick.index([1e308, 1.0, 1e308], 0.49), 0)
	assert_eq(LFWeightedPick.index([1e308, 1.0, 1e308], 0.51), 2)


func test_index_by_picks_by_share_when_the_total_overflows():
	var huge := [1e308, 1e308, 1e308]
	var weight_at := func(i: int) -> float: return huge[i]
	assert_eq(LFWeightedPick.index_by(3, weight_at, 0.0), 0)
	assert_eq(LFWeightedPick.index_by(3, weight_at, 0.5), 1)
	assert_eq(LFWeightedPick.index_by(3, weight_at, 0.9), 2)


func test_index_by_calls_weight_at_at_most_twice_per_considered_index():
	var weights := [1.0, 0.0, 2.0, -1.0, 3.0, 0.0]
	var calls := {}
	var weight_at := func(i: int) -> float:
		calls[i] = calls.get(i, 0) + 1
		return weights[i]
	for roll in [0.0, 0.5, 0.99, 1.0]:
		calls.clear()
		LFWeightedPick.index_by(weights.size(), weight_at, roll, 1)
		assert_false(calls.has(0), 'an index before from is never read')
		for i in calls:
			assert_lte(calls[i], 2, 'index %d, roll %s' % [i, roll])


func test_picks_follow_the_weights_over_many_rolls():
	var random := LFRandom.new(1234)
	var counts := [0, 0, 0]
	for i in 6000:
		counts[LFWeightedPick.index([70.0, 25.0, 5.0], random.randf())] += 1
	assert_almost_eq(counts[0] / 6000.0, 0.70, 0.03)
	assert_almost_eq(counts[1] / 6000.0, 0.25, 0.03)
	assert_almost_eq(counts[2] / 6000.0, 0.05, 0.02)
