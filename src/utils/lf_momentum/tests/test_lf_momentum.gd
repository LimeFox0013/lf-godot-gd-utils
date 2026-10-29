extends GutTest

var momentum: LFMomentum


func before_each():
	momentum = LFMomentum.new(10.0, 30.0, 4.0)


func test_starts_on_the_base():
	assert_eq(momentum.value, 10.0)
	assert_eq(momentum.ratio(), 0.0)
	assert_false(momentum.is_built_up())


func test_bump_adds_up_to_the_cap():
	assert_eq(momentum.bump(5.0), 15.0)
	assert_eq(momentum.bump(100.0), 30.0)
	assert_eq(momentum.ratio(), 1.0)


func test_ratio_is_between_base_and_cap():
	momentum.bump(5.0)
	assert_almost_eq(momentum.ratio(), 0.25, 0.0001)


func test_step_does_not_decay_unless_slowing():
	momentum.bump(10.0)
	for i in 100:
		momentum.step(0.1, false)
	assert_eq(momentum.value, 20.0)


func test_step_decays_per_second_while_slowing_and_stops_at_the_base():
	momentum.bump(10.0)
	assert_almost_eq(momentum.step(1.0, true), 16.0, 0.0001)
	assert_eq(momentum.step(100.0, true), 10.0)
	assert_false(momentum.is_built_up())


func test_decay_is_off_again_as_soon_as_the_flag_is_false():
	momentum.bump(10.0)
	momentum.step(1.0, true)
	var after_slowing := momentum.value
	momentum.step(1.0, false)
	momentum.step(1.0, false)
	assert_eq(momentum.value, after_slowing, 'no latch: nothing decays once slowing stops')
	momentum.bump(1.0)
	momentum.step(0.0, false)
	assert_eq(momentum.value, after_slowing + 1.0)


func test_a_bump_after_decay_builds_on_what_is_left():
	momentum.bump(10.0)
	momentum.step(1.0, true)
	assert_eq(momentum.bump(2.0), 18.0)


func test_a_negative_or_non_finite_delta_changes_nothing():
	momentum.bump(10.0)
	momentum.step(-1.0, true)
	momentum.step(NAN, true)
	momentum.step(INF, true)
	assert_eq(momentum.value, 20.0)


func test_penalize_removes_a_fraction_of_the_value():
	momentum.bump(10.0)
	assert_almost_eq(momentum.penalize(0.25), 15.0, 0.0001)


func test_penalize_never_goes_below_the_base():
	assert_eq(momentum.penalize(0.9), 10.0)
	momentum.bump(10.0)
	assert_eq(momentum.penalize(1.0), 10.0)


func test_penalize_rejects_a_fraction_outside_zero_to_one():
	momentum.bump(10.0)
	for bad in [-0.1, 1.1, NAN]:
		momentum.penalize(bad)
	assert_push_error_count(3)
	assert_eq(momentum.value, 20.0)


func test_bump_rejects_negative_nan_and_infinite_amounts():
	for bad in [-1.0, NAN, INF]:
		momentum.bump(bad)
	assert_push_error_count(3)
	assert_eq(momentum.value, 10.0)


func test_reset_returns_to_the_base():
	momentum.bump(10.0)
	momentum.reset()
	assert_eq(momentum.value, 10.0)


func test_by_default_the_cap_is_the_base_and_the_ratio_is_zero():
	var flat := LFMomentum.new(3.0)
	assert_eq(flat.cap, 3.0)
	assert_eq(flat.bump(5.0), 3.0)
	assert_eq(flat.ratio(), 0.0)


func test_a_cap_below_the_base_is_reported_and_the_base_is_used():
	var bad := LFMomentum.new(5.0, 2.0)
	assert_push_error('cap')
	assert_eq(bad.cap, 5.0)


func test_raising_the_base_lifts_the_value_and_the_cap():
	momentum.base = 40.0
	assert_eq(momentum.value, 40.0)
	assert_eq(momentum.cap, 40.0)


func test_lowering_the_cap_clamps_the_value():
	momentum.bump(15.0)
	momentum.cap = 20.0
	assert_eq(momentum.value, 20.0)


func test_a_negative_decay_is_reported_and_ignored():
	momentum.decay_per_second = -1.0
	assert_push_error('decay')
	assert_eq(momentum.decay_per_second, 4.0)


func test_ratio_feeds_a_jump_strength():
	var physics := LFJumpPhysics.new()
	momentum.bump(20.0)
	var strong := physics.jump_strength(10.0, 1.0, momentum.ratio())
	assert_gt(strong, physics.jump_strength(10.0, 1.0, 0.0))


func test_a_negative_base_with_the_default_cap_has_the_cap_on_the_base():
	var flat := LFMomentum.new(-5.0)
	assert_eq(flat.cap, -5.0)
	assert_eq(flat.value, -5.0)
	assert_eq(flat.bump(3.0), -5.0)


func test_a_negative_base_with_a_cap_below_it_uses_the_base():
	var bad := LFMomentum.new(-5.0, -8.0)
	assert_push_error('cap')
	assert_eq(bad.cap, -5.0)
