extends GutTest

## One frame at 60 frames per second.
const FRAME := 1.0 / 60.0


func test_it_rises_towards_a_higher_target_without_overshooting():
	var follow := LFRatchetFollow.new(2.0)
	var value := 0.0
	for i in 600:
		var next := follow.step(value, 10.0, FRAME)
		assert_between(next, value, 10.0)
		value = next
	assert_almost_eq(value, 10.0, 0.001)


func test_the_rise_is_the_same_at_any_frame_rate():
	var follow := LFRatchetFollow.new(2.0)
	var coarse := follow.step(0.0, 10.0, 0.5)
	var fine := 0.0
	for i in 50:
		fine = follow.step(fine, 10.0, 0.01)
	assert_almost_eq(coarse, fine, 0.0001)


func test_a_lower_target_sinks_at_the_sink_speed():
	var follow := LFRatchetFollow.new(2.0, 1.0)
	assert_almost_eq(follow.step(5.0, 0.0, 0.5), 4.5, 0.0001)


func test_the_sink_stops_at_the_target():
	var follow := LFRatchetFollow.new(2.0, 100.0)
	assert_eq(follow.step(5.0, 4.9, 1.0), 4.9)
	assert_eq(follow.step(4.9, 4.9, 1.0), 4.9, "at the target it stays")


func test_without_a_sink_speed_it_never_drops():
	var follow := LFRatchetFollow.new(2.0)
	assert_eq(follow.step(5.0, 0.0, 1.0), 5.0)


func test_the_offset_shifts_the_target():
	var follow := LFRatchetFollow.new(1000.0)
	follow.offset = -4.5
	assert_almost_eq(follow.step(0.0, 10.0, 1.0), 5.5, 0.0001)


func test_the_minimum_keeps_a_low_target_from_pulling_the_value_down():
	var follow := LFRatchetFollow.new(1000.0, 100.0)
	follow.min_value = 0.0
	follow.offset = -4.5
	assert_eq(follow.step(0.0, 2.0, 1.0), 0.0, "target + offset is below the minimum")
	assert_eq(follow.step(3.0, 2.0, 1.0), 0.0, "sinks only down to the minimum")


func test_a_follow_speed_of_zero_or_less_never_rises():
	var follow := LFRatchetFollow.new(0.0)
	assert_eq(follow.step(1.0, 9.0, 1.0), 1.0)
	follow.follow_speed = -3.0
	assert_eq(follow.step(1.0, 9.0, 1.0), 1.0)


func test_a_non_positive_delta_or_a_nan_changes_nothing():
	var follow := LFRatchetFollow.new(2.0, 1.0)
	assert_eq(follow.step(1.0, 9.0, 0.0), 1.0)
	assert_eq(follow.step(1.0, 9.0, -1.0), 1.0)
	assert_eq(follow.step(1.0, NAN, 1.0), 1.0)
	assert_eq(follow.step(1.0, 9.0, NAN), 1.0)
	assert_true(is_nan(follow.step(NAN, 9.0, 1.0)))


func test_defaults_are_the_documented_ones():
	var follow := LFRatchetFollow.new()
	assert_eq(follow.follow_speed, LFRatchetFollow.DEFAULT_FOLLOW_SPEED)
	assert_eq(follow.sink_speed, 0.0)
	assert_eq(follow.offset, 0.0)
	assert_eq(follow.min_value, -INF)


func test_a_negative_sink_speed_never_raises_the_value():
	var follow := LFRatchetFollow.new(2.0, -5.0)
	assert_eq(follow.step(5.0, 0.0, 1.0), 5.0)
