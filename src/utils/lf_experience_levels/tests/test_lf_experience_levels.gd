extends GutTest

var track: LFExperienceLevels
var reached: Array[int]


func before_each():
	track = LFExperienceLevels.new([10, 20, 40])
	reached = []
	track.leveled_up.connect(func(new_level: int): reached.append(new_level))


func test_starts_at_level_zero_with_no_experience():
	assert_eq(track.level, 0)
	assert_eq(track.experience, 0.0)
	assert_eq(track.max_level, 3)
	assert_false(track.is_max())


func test_gain_below_the_threshold_keeps_the_level_and_adds_progress():
	assert_eq(track.gain(4.0), 0)
	assert_eq(track.level, 0)
	assert_eq(track.experience, 4.0)
	assert_almost_eq(track.progress(), 0.4, 0.0001)
	assert_eq(reached, [])


func test_gain_at_the_exact_threshold_levels_up_with_no_remainder():
	assert_eq(track.gain(10.0), 1)
	assert_eq(track.level, 1)
	assert_eq(track.experience, 0.0)
	assert_eq(reached, [1])


func test_overflow_carries_across_several_levels():
	assert_eq(track.gain(35.0), 2)
	assert_eq(track.level, 2)
	assert_eq(track.experience, 5.0)
	assert_eq(reached, [1, 2])
	assert_eq(track.next_threshold(), 40.0)


func test_experience_beyond_the_top_level_is_dropped():
	assert_eq(track.gain(1000.0), 3)
	assert_true(track.is_max())
	assert_eq(track.level, 3)
	assert_eq(track.experience, 0.0)
	assert_eq(track.progress(), 1.0)
	assert_eq(track.next_threshold(), INF)
	assert_eq(reached, [1, 2, 3])


func test_gain_at_the_top_level_does_nothing_and_is_silent():
	track.gain(1000.0)
	var amounts: Array[float] = []
	track.experience_gained.connect(func(a: float): amounts.append(a))
	assert_eq(track.gain(5.0), 0)
	assert_eq(amounts, [])
	assert_eq(reached, [1, 2, 3])


func test_experience_gained_fires_once_after_the_level_ups():
	var order: Array[String] = []
	track.leveled_up.connect(func(_l: int): order.append("level"))
	track.experience_gained.connect(func(a: float): order.append("gained %s" % a))
	track.gain(35.0)
	assert_eq(order, ["level", "level", "gained 35.0"])


func test_zero_gain_is_accepted():
	var amounts: Array[float] = []
	track.experience_gained.connect(func(a: float): amounts.append(a))
	assert_eq(track.gain(0.0), 0)
	assert_eq(amounts, [0.0])


func test_negative_and_nan_gains_are_rejected():
	track.gain(5.0)
	assert_eq(track.gain(-3.0), 0)
	assert_eq(track.gain(NAN), 0)
	assert_eq(track.experience, 5.0)
	assert_eq(track.level, 0)
	assert_push_error_count(2)


func test_a_zero_threshold_is_passed_at_once_and_does_not_divide_by_zero():
	var zero := LFExperienceLevels.new([0, 5])
	assert_eq(zero.progress(), 1.0)
	assert_eq(zero.gain(0.0), 1)
	assert_eq(zero.level, 1)
	assert_almost_eq(zero.progress(), 0.0, 0.0001)
	assert_eq(zero.gain(5.0), 1)
	assert_true(zero.is_max())


func test_set_level_checks_the_new_level_not_the_old_one():
	assert_false(track.set_level(4))
	assert_eq(track.level, 0)
	assert_false(track.set_level(-1))
	assert_push_error_count(2)
	assert_true(track.set_level(3))
	assert_true(track.is_max())
	assert_eq(track.level, 3)


func test_set_level_clears_experience_and_emits_nothing():
	track.gain(4.0)
	assert_true(track.set_level(2))
	assert_eq(track.experience, 0.0)
	assert_eq(reached, [])


func test_reset_goes_back_to_level_zero():
	track.gain(35.0)
	track.reset()
	assert_eq(track.level, 0)
	assert_eq(track.experience, 0.0)
	assert_eq(track.max_level, 3)


func test_start_level_is_used_and_an_invalid_one_falls_back_to_zero():
	assert_eq(LFExperienceLevels.new([10, 20], 1).level, 1)
	assert_eq(LFExperienceLevels.new([10, 20], 5).level, 0)
	assert_push_error('LFExperienceLevels')


func test_a_track_without_thresholds_is_at_its_top_level():
	var empty := LFExperienceLevels.new()
	assert_true(empty.is_max())
	assert_eq(empty.max_level, 0)
	assert_eq(empty.progress(), 1.0)
	assert_eq(empty.gain(10.0), 0)


func test_bad_thresholds_count_as_zero():
	var bad := LFExperienceLevels.new([-5, "x", 10])
	assert_eq(bad.get_thresholds(), PackedFloat64Array([0.0, 0.0, 10.0]))
	assert_push_error_count(2)


func test_set_thresholds_replaces_the_track():
	track.gain(15.0)
	track.set_thresholds([3, 3], 1)
	assert_eq(track.max_level, 2)
	assert_eq(track.level, 1)
	assert_eq(track.experience, 0.0)


func test_get_thresholds_returns_a_copy():
	var copy := track.get_thresholds()
	copy[0] = 999.0
	assert_eq(track.next_threshold(), 10.0)


func test_progress_runs_from_zero_to_one_within_a_level():
	track.gain(10.0)
	track.gain(5.0)
	assert_almost_eq(track.progress(), 0.25, 0.0001)


func test_infinite_gain_is_rejected():
	assert_eq(track.gain(INF), 0)
	assert_eq(track.experience, 0.0)
	assert_push_error_count(1)


func test_start_level_at_max_is_accepted():
	var full := LFExperienceLevels.new([10, 20], 2)
	assert_eq(full.level, 2)
	assert_true(full.is_max())
	assert_eq(full.gain(5.0), 0)


func test_fractional_gains_add_up():
	track.gain(2.5)
	track.gain(2.5)
	assert_eq(track.experience, 5.0)
	assert_almost_eq(track.progress(), 0.5, 0.0001)


func test_set_thresholds_with_invalid_start_level_starts_at_zero():
	track.gain(15.0)
	track.set_thresholds([3, 3], 9)
	assert_eq(track.level, 0)
	assert_eq(track.max_level, 2)
	assert_push_error_count(1)


func test_set_thresholds_and_reset_emit_no_level_up():
	track.set_thresholds([1, 1], 1)
	track.reset()
	assert_eq(reached, [])
