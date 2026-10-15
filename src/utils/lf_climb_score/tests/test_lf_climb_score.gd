extends GutTest

var s: LFClimbScore


func before_each():
	s = LFClimbScore.new()


## Climbs `metres` over `seconds` in 0.1 s frames from the current peak.
func _climb(metres: float, seconds: float, mult := 1.0, min_rate := 0.0) -> void:
	var frames := int(seconds / 0.1)
	var from := s.peak
	for i in frames:
		s.step(from + metres * float(i + 1) / frames, mult, min_rate, 0.1)


func test_starts_at_zero():
	assert_eq(s.score, 0.0)
	assert_eq(s.peak, 0.0)


func test_climbing_earns_new_height_times_multiplier():
	_climb(10.0, 2.0, 2.0)
	assert_almost_eq(s.score, 20.0, 0.001)
	assert_almost_eq(s.peak, 10.0, 0.001)


func test_falling_earns_and_loses_nothing():
	_climb(10.0, 2.0)
	var before := s.score
	s.step(2.0, 1.0, 0.0, 0.1)
	assert_eq(s.score, before)
	assert_almost_eq(s.peak, 10.0, 0.001)


func test_regaining_a_reached_height_earns_nothing():
	_climb(10.0, 2.0)
	s.step(2.0, 1.0, 0.0, 0.1)
	var before := s.score
	s.step(10.0, 1.0, 0.0, 0.1)
	assert_eq(s.score, before)
	s.step(11.0, 1.0, 0.0, 0.1)
	assert_almost_eq(s.score, before + 1.0, 0.001)


func test_the_multiplier_in_force_when_height_is_gained_is_the_one_paid():
	s.step(1.0, 1.0, 0.0, 0.1)
	s.step(2.0, 3.0, 0.0, 0.1)
	assert_almost_eq(s.score, 1.0 + 3.0, 0.001)


func test_a_climb_no_faster_than_the_minimum_earns_nothing():
	# 0.5 m/s with a minimum of 1 m/s.
	_climb(2.5, 5.0, 1.0, 1.0)
	assert_eq(s.score, 0.0)
	assert_almost_eq(s.peak, 2.5, 0.001, 'the peak still rises')


func test_slow_height_is_not_paid_later():
	_climb(2.5, 5.0, 1.0, 1.0)
	s.step(2.5, 1.0, 1.0, 0.1)
	assert_eq(s.score, 0.0)


func test_a_fast_climb_after_a_slow_one_earns_only_the_new_part():
	_climb(2.5, 5.0, 1.0, 1.0)
	_climb(10.0, 1.0, 1.0, 1.0)
	assert_gt(s.score, 0.0)
	assert_lt(s.score, 10.0 + 0.001)


func test_a_zero_multiplier_earns_nothing():
	_climb(5.0, 1.0, 0.0)
	assert_eq(s.score, 0.0)


func test_changed_fires_only_when_the_score_rose():
	var seen := []
	s.changed.connect(func(v: float) -> void: seen.append(v))
	s.step(1.0, 1.0, 0.0, 0.1)
	s.step(0.5, 1.0, 0.0, 0.1)
	assert_eq(seen.size(), 1)


func test_reset_clears_score_and_sets_the_peak():
	_climb(5.0, 1.0)
	s.reset(3.0)
	assert_eq(s.score, 0.0)
	assert_eq(s.peak, 3.0)
	s.step(3.5, 1.0, 0.0, 0.1)
	assert_almost_eq(s.score, 0.5, 0.001)


func test_non_finite_input_changes_nothing():
	s.step(NAN, 1.0, 0.0, 0.1)
	s.step(1.0, INF, 0.0, 0.1)
	s.step(1.0, 1.0, 0.0, -1.0)
	assert_eq(s.score, 0.0)
	assert_eq(s.peak, 0.0)
	assert_push_error_count(3)


func test_a_bad_window_uses_the_default():
	var bad := LFClimbScore.new(0.0)
	assert_push_error_count(1)
	bad.step(1.0, 1.0, 0.0, 0.1)
	assert_gt(bad.score, 0.0)
