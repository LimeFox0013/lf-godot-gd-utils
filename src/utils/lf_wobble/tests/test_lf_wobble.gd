extends GutTest

## One frame at 60 frames per second.
const FRAME := 1.0 / 60.0


func _settle(wobble: LFWobble, seconds: float) -> void:
	for i in int(seconds / FRAME):
		wobble.step(FRAME)


func test_it_rests_at_zero():
	var wobble := LFWobble.new()
	_settle(wobble, 1.0)
	assert_eq(wobble.value, 0.0)
	assert_eq(wobble.velocity, 0.0)


func test_a_kick_swings_it_out_and_back_past_rest():
	var wobble := LFWobble.new(160.0, 4.0)
	wobble.kick(2.0)
	var highest := 0.0
	var lowest := 0.0
	for i in 60:
		wobble.step(FRAME)
		highest = maxf(highest, wobble.value)
		lowest = minf(lowest, wobble.value)
	assert_gt(highest, 0.05, 'it swings out')
	assert_lt(lowest, -0.001, 'it overshoots to the other side')


func test_it_settles_to_rest_after_a_kick():
	var wobble := LFWobble.new()
	wobble.kick(3.0)
	_settle(wobble, 4.0)
	assert_almost_eq(wobble.value, 0.0, 0.001)
	assert_almost_eq(wobble.velocity, 0.0, 0.01)


func test_a_steady_drive_holds_it_at_drive_over_stiffness():
	var wobble := LFWobble.new(100.0, 20.0)
	for i in 300:
		wobble.step(FRAME, 50.0)
	assert_almost_eq(wobble.value, 0.5, 0.001)


func test_damping_that_is_critical_does_not_overshoot():
	var wobble := LFWobble.new(100.0, 20.0)
	wobble.kick(5.0)
	for i in 300:
		wobble.step(FRAME)
		assert_gte(wobble.value, -0.0001)


func test_the_limit_stops_it_and_drops_its_outward_speed():
	var wobble := LFWobble.new()
	wobble.limit = 0.3
	wobble.kick(100.0)
	wobble.step(FRAME)
	assert_almost_eq(wobble.value, 0.3, 0.01)
	assert_lte(wobble.velocity, 0.0, 'it is not still flying outward')
	wobble.kick(-100.0)
	wobble.step(FRAME)
	assert_lt(wobble.value, 0.3)


func test_a_slow_frame_matches_many_fast_ones():
	var coarse := LFWobble.new()
	var fine := LFWobble.new()
	coarse.kick(2.0)
	fine.kick(2.0)
	coarse.step(0.1)
	for i in 12:
		fine.step(0.1 / 12.0)
	assert_almost_eq(coarse.value, fine.value, 0.01)


func test_a_huge_delta_does_not_blow_it_up():
	var wobble := LFWobble.new()
	wobble.kick(1.0)
	wobble.step(5.0)
	assert_true(is_finite(wobble.value))
	assert_lt(absf(wobble.value), 10.0)


func test_a_delta_of_zero_or_nan_changes_nothing():
	var wobble := LFWobble.new()
	wobble.kick(1.0)
	wobble.step(0.0)
	wobble.step(NAN)
	wobble.step(FRAME, NAN)
	assert_eq(wobble.value, 0.0)
	assert_eq(wobble.velocity, 1.0)


func test_kick_with_nan_is_ignored_and_reset_clears():
	var wobble := LFWobble.new()
	wobble.kick(NAN)
	assert_eq(wobble.velocity, 0.0)
	wobble.kick(2.0)
	wobble.step(FRAME)
	wobble.reset()
	assert_eq(wobble.value, 0.0)
	assert_eq(wobble.velocity, 0.0)
