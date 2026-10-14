extends GutTest

var streak: LFStreakMultiplier
var changes: Array = []


func before_each():
	streak = LFStreakMultiplier.new()
	changes = []
	streak.changed.connect(func(v: float) -> void: changes.append(v))


func test_starts_at_the_base_with_no_hits():
	assert_eq(streak.value, LFStreakMultiplier.DEFAULT_BASE)
	assert_eq(streak.count, 0)


func test_first_hit_raises_the_value_by_one_step():
	assert_almost_eq(streak.hit(), 1.2, 0.0001)
	assert_eq(streak.count, 1)


func test_n_hits_equal_base_plus_n_steps():
	for i in 7:
		streak.hit()
	assert_almost_eq(streak.value, 1.0 + 7 * 0.2, 0.0001)


func test_the_ceiling_holds():
	for i in 100:
		streak.hit()
	assert_eq(streak.value, LFStreakMultiplier.DEFAULT_CEILING)


func test_reset_returns_to_base_and_count_zero():
	streak.hit()
	streak.hit()
	streak.reset()
	assert_eq(streak.value, LFStreakMultiplier.DEFAULT_BASE)
	assert_eq(streak.count, 0)


func test_changed_fires_after_each_hit_that_changes_the_value():
	streak.hit()
	streak.hit()
	assert_eq(changes.size(), 2)
	assert_almost_eq(changes[1], 1.4, 0.0001)


func test_changed_does_not_fire_for_a_hit_at_the_ceiling():
	streak = LFStreakMultiplier.new(1.0, 1.0, 2.0)
	streak.changed.connect(func(v: float) -> void: changes.append(v))
	streak.hit()
	streak.hit()
	streak.hit()
	assert_eq(changes, [2.0])


func test_changed_fires_on_a_reset_that_changes_the_value():
	streak.hit()
	streak.reset()
	assert_eq(changes.size(), 2)
	assert_eq(changes[1], 1.0)


func test_reset_at_the_base_fires_nothing():
	streak.reset()
	assert_eq(changes.size(), 0)


func test_count_keeps_counting_hits_at_the_ceiling_until_reset():
	streak = LFStreakMultiplier.new(1.0, 1.0, 2.0)
	for i in 5:
		streak.hit()
	assert_eq(streak.value, 2.0)
	assert_eq(streak.count, 5)
	streak.reset()
	assert_eq(streak.count, 0)


func test_no_float_drift_after_a_thousand_hits():
	streak = LFStreakMultiplier.new(1.0, 0.1, 1000.0)
	for i in 1000:
		streak.hit()
	assert_eq(streak.value, 1.0 + 0.1 * 1000)


func test_a_step_of_zero_or_less_falls_back_to_the_default_with_a_report():
	streak = LFStreakMultiplier.new(1.0, 0.0)
	assert_push_error_count(1)
	assert_almost_eq(streak.hit(), 1.0 + LFStreakMultiplier.DEFAULT_STEP, 0.0001)


func test_a_ceiling_below_the_base_falls_back_with_a_report():
	streak = LFStreakMultiplier.new(2.0, 0.5, 1.0)
	assert_push_error_count(1)
	assert_eq(streak.hit(), 2.5)


func test_nan_and_infinite_arguments_fall_back_with_a_report():
	streak = LFStreakMultiplier.new(NAN, NAN, INF)
	assert_push_error_count(3)
	assert_eq(streak.value, LFStreakMultiplier.DEFAULT_BASE)
	assert_almost_eq(streak.hit(), 1.0 + LFStreakMultiplier.DEFAULT_STEP, 0.0001)


func test_a_negative_base_is_allowed():
	streak = LFStreakMultiplier.new(-1.0, 0.5, 1.0)
	assert_eq(streak.value, -1.0)
	assert_eq(streak.hit(), -0.5)
	streak.reset()
	assert_eq(streak.value, -1.0)
