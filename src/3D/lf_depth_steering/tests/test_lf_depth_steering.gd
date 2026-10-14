extends GutTest

const RISE := 20.0
const FALL := 30.0
const DELTA := 1.0 / 60.0

var steering: LFDepthSteering


func before_each() -> void:
	steering = LFDepthSteering.new()


func _platform(center_z: float, bottom: float, top: float, center_x := 0.0, half_x := 1.0, half_z := 0.5, id: Variant = null) -> LFDepthSteering.Footprint:
	var footprint := LFDepthSteering.Footprint.new()
	footprint.id = id
	footprint.center_x = center_x
	footprint.half_x = half_x
	footprint.center_z = center_z
	footprint.half_z = half_z
	footprint.bottom = bottom
	footprint.top = top
	footprint.land_half_x = half_x
	footprint.land_half_z = half_z
	return footprint


func _run(z: float, target: float, time: float) -> Array[Vector2]:
	var states: Array[Vector2] = []
	var state := Vector2(z, 0.0)
	var left := time
	while left > 0.0:
		state = steering.step(state.x, state.y, target, DELTA, left)
		states.append(state)
		left -= DELTA
	return states


func test_apex_height_adds_the_rise() -> void:
	assert_almost_eq(LFDepthSteering.apex_height(1.0, 10.0, RISE), 3.5, 0.0001)


func test_apex_height_is_the_height_when_not_rising() -> void:
	assert_eq(LFDepthSteering.apex_height(1.0, -4.0, RISE), 1.0)


func test_time_to_apex_is_velocity_over_gravity_and_zero_when_falling() -> void:
	assert_almost_eq(LFDepthSteering.time_to_apex(10.0, RISE), 0.5, 0.0001)
	assert_eq(LFDepthSteering.time_to_apex(-3.0, RISE), 0.0)


func test_landing_on_a_flat_tower_is_the_highest_platform_below_the_apex() -> void:
	var low := _platform(1.0, 0.0, 1.0)
	var high := _platform(-1.0, 1.5, 2.0)
	var result := steering.landing(Vector3(0, 2.2, 0), 0.0, 0.0, RISE, FALL, [low, high])
	assert_eq(result.footprint, high)
	assert_eq(result.z, -1.0)


func test_landing_time_is_the_fall_to_the_top() -> void:
	var platform := _platform(1.0, 0.0, 1.0)
	var result := steering.landing(Vector3(0, 2.0, 0), 0.0, 0.0, RISE, FALL, [platform])
	assert_almost_eq(result.time, sqrt(2.0 * 1.0 / FALL), 0.0001)


func test_landing_time_includes_the_rise_to_the_apex() -> void:
	var platform := _platform(1.0, 0.0, 1.0)
	var result := steering.landing(Vector3(0, 1.0, 0), 10.0, 0.0, RISE, FALL, [platform])
	var apex_y := 1.0 + 100.0 / 40.0
	assert_almost_eq(result.time, 0.5 + sqrt(2.0 * (apex_y - 1.0) / FALL), 0.0001)


func test_landing_on_a_tilted_tower_picks_the_highest_reachable_not_the_nearest_in_depth() -> void:
	var near := _platform(0.2, 0.0, 1.0)
	var middle := _platform(1.5, 0.5, 1.4)
	var far := _platform(3.0, 1.0, 1.8)
	var result := steering.landing(Vector3(0, 3.0, 0), 0.0, 0.0, RISE, FALL, [near, middle, far])
	assert_eq(result.footprint, far)


func test_landing_ignores_platforms_above_the_apex() -> void:
	var above := _platform(1.0, 5.0, 6.0)
	var below := _platform(-1.0, 0.0, 1.0)
	var result := steering.landing(Vector3(0, 2.0, 0), 0.0, 0.0, RISE, FALL, [above, below])
	assert_eq(result.footprint, below)


func test_landing_is_null_when_every_top_is_above_the_apex() -> void:
	var above := _platform(1.0, 5.0, 6.0)
	assert_null(steering.landing(Vector3(0, 2.0, 0), 5.0, 0.0, RISE, FALL, [above]))


func test_landing_is_null_when_nothing_is_below_in_x() -> void:
	var aside := _platform(1.0, 0.0, 1.0, 10.0)
	assert_null(steering.landing(Vector3(0, 3.0, 0), 0.0, 0.0, RISE, FALL, [aside]))


func test_landing_reaches_the_platform_by_the_feet_half_width() -> void:
	var platform := _platform(1.0, 0.0, 1.0, 0.0, 1.0)
	assert_not_null(steering.landing(Vector3(1.2, 3.0, 0), 0.0, 0.0, RISE, FALL, [platform]))
	assert_null(steering.landing(Vector3(1.3, 3.0, 0), 0.0, 0.0, RISE, FALL, [platform]))


func test_landing_changes_with_velocity_x_because_the_crossing_x_moves() -> void:
	var under := _platform(1.0, 0.0, 1.0, 0.0)
	var ahead := _platform(-1.0, 0.0, 0.5, 3.3)
	var still := steering.landing(Vector3(0, 3.0, 0), 0.0, 0.0, RISE, FALL, [under, ahead])
	var running := steering.landing(Vector3(0, 3.0, 0), 0.0, 8.0, RISE, FALL, [under, ahead])
	assert_eq(still.footprint, under)
	assert_eq(running.footprint, ahead)


func test_landing_may_be_a_platform_passed_on_the_way_up() -> void:
	var passed := _platform(1.0, 1.0, 2.0)
	var result := steering.landing(Vector3(0, 0.0, 0), 12.0, 0.0, RISE, FALL, [passed])
	assert_eq(result.footprint, passed)


func test_landing_from_a_falling_start_uses_the_current_height_as_the_apex() -> void:
	var platform := _platform(1.0, 0.0, 1.0)
	var result := steering.landing(Vector3(0, 2.0, 0), -6.0, 0.0, RISE, FALL, [platform])
	assert_almost_eq(result.time, sqrt(2.0 / FALL), 0.0001)


func test_landing_on_equal_tops_takes_the_nearest_in_depth() -> void:
	var far := _platform(4.0, 0.0, 1.0)
	var near := _platform(0.5, 0.0, 1.0)
	var result := steering.landing(Vector3(0, 2.0, 0), 0.0, 0.0, RISE, FALL, [far, near])
	assert_eq(result.footprint, near)


func test_dodge_goes_toward_the_preferred_side() -> void:
	var overhead := _platform(0.0, 2.0, 3.0)
	var reach := 0.5 + 0.25 + 0.2
	var toward_back := steering.dodge(Vector3(0, 1.0, 0.1), 10.0, 0.0, RISE, [overhead], -5.0)
	var toward_front := steering.dodge(Vector3(0, 1.0, 0.1), 10.0, 0.0, RISE, [overhead], 5.0)
	assert_almost_eq(toward_back.z, -reach, 0.0001)
	assert_almost_eq(toward_front.z, reach, 0.0001)


func test_dodge_prefers_the_side_even_when_it_is_the_farther_edge() -> void:
	var overhead := _platform(0.0, 2.0, 3.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.8), 10.0, 0.0, RISE, [overhead], -5.0)
	assert_almost_eq(result.z, -0.95, 0.0001)


func test_dodge_without_a_side_takes_the_nearest_edge() -> void:
	var overhead := _platform(0.0, 2.0, 3.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.5), 10.0, 0.0, RISE, [overhead], 0.5)
	assert_almost_eq(result.z, 0.95, 0.0001)


func test_dodge_ties_go_toward_zero() -> void:
	var overhead := _platform(2.0, 2.0, 3.0, 0.0, 1.0, 0.5)
	var result := steering.dodge(Vector3(0, 1.0, 2.0), 10.0, 0.0, RISE, [overhead], 2.0)
	assert_almost_eq(result.z, 1.05, 0.0001)


func test_dodge_goes_around_a_second_platform_on_the_preferred_side() -> void:
	var first := _platform(0.0, 2.0, 3.0)
	var second := _platform(1.4, 2.0, 3.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [first, second], 5.0)
	assert_almost_eq(result.z, 1.4 + 0.95, 0.0001)


func test_dodge_forbidden_bands_merge_into_one() -> void:
	var first := _platform(0.0, 2.0, 3.0)
	var second := _platform(1.4, 2.0, 3.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [first, second], -5.0)
	assert_almost_eq(result.z, -0.95, 0.0001)


func test_dodge_never_crosses_a_separate_blocker_band() -> void:
	var inner := _platform(0.0, 2.0, 3.0, 0.0, 1.0, 0.1)
	var outer := _platform(1.6, 2.0, 3.0, 0.0, 1.0, 0.1)
	var result := steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [inner, outer], 5.0)
	assert_almost_eq(result.z, 0.55, 0.0001)


func test_dodge_is_null_when_the_depth_is_already_free() -> void:
	var overhead := _platform(0.0, 2.0, 3.0)
	assert_null(steering.dodge(Vector3(0, 1.0, 3.0), 10.0, 0.0, RISE, [overhead], 0.0))


func test_dodge_is_null_when_the_head_stays_below_the_bottom() -> void:
	var overhead := _platform(0.0, 9.0, 10.0)
	assert_null(steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [overhead], 0.0))


func test_dodge_has_no_blocker_once_the_feet_are_above_the_top() -> void:
	var below := _platform(0.0, 0.0, 1.0)
	assert_null(steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [below], 0.0))


func test_dodge_is_null_when_falling_clear_of_everything() -> void:
	var overhead := _platform(0.0, 4.0, 5.0)
	assert_null(steering.dodge(Vector3(0, 1.0, 0.0), -3.0, 0.0, RISE, [overhead], 0.0))


func test_dodge_blocker_x_band_widens_by_the_look_ahead() -> void:
	var overhead := _platform(0.0, 2.0, 3.0, 1.8, 0.5)
	assert_null(steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [overhead], 0.0))
	assert_not_null(steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 10.0, RISE, [overhead], 0.0))


func test_dodge_ignores_a_platform_beside_the_body_in_x() -> void:
	var aside := _platform(0.0, 2.0, 3.0, 5.0)
	assert_null(steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [aside], 0.0))


func test_dodge_time_is_when_the_bottom_meets_the_head() -> void:
	var overhead := _platform(0.0, 3.0, 4.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.0), 10.0, 0.0, RISE, [overhead], 1.0)
	var head := 1.0 + 1.58
	var expected := (10.0 - sqrt(100.0 - 2.0 * RISE * (3.0 - head))) / RISE
	assert_almost_eq(result.time, expected, 0.0001)


func test_dodge_time_is_zero_when_already_level_with_the_platform() -> void:
	var around := _platform(0.0, 1.0, 3.0)
	var result := steering.dodge(Vector3(0, 1.5, 0.0), 0.0, 0.0, RISE, [around], 1.0)
	assert_eq(result.time, 0.0)


func test_dodge_time_is_the_earliest_blocker() -> void:
	var late := _platform(0.0, 5.0, 6.0)
	var early := _platform(0.2, 3.0, 4.0)
	var result := steering.dodge(Vector3(0, 1.0, 0.0), 12.0, 0.0, RISE, [late, early], 1.0)
	var alone := steering.dodge(Vector3(0, 1.0, 0.0), 12.0, 0.0, RISE, [early], 1.0)
	assert_almost_eq(result.time, alone.time, 0.0001)


func test_step_never_overshoots() -> void:
	for state in _run(0.0, 2.0, 0.6):
		assert_true(state.x <= 2.0 + 0.0001)


func test_step_arrives_by_time_left_even_for_a_long_distance() -> void:
	var states := _run(0.0, 30.0, 0.1)
	assert_eq(states[-1].x, 30.0)
	assert_eq(states[-1].y, 0.0)


func test_step_eases_in_from_rest() -> void:
	var states := _run(0.0, 2.0, 1.0)
	var fastest := 0.0
	var previous := 0.0
	for state in states:
		fastest = maxf(fastest, state.x - previous)
		previous = state.x
	assert_lt(states[0].x, fastest * 0.5)


func test_step_eases_out_into_the_target() -> void:
	var states := _run(0.0, 2.0, 1.0)
	var last_gap := states[-1].x - states[-2].x
	var peak := 0.0
	for index in range(1, states.size()):
		peak = maxf(peak, states[index].x - states[index - 1].x)
	assert_lt(last_gap, peak * 0.2)


func test_step_switching_the_target_moves_less_than_a_snap_to_it() -> void:
	var state := Vector2(0.0, 0.0)
	var left := 1.0
	for _i in 20:
		state = steering.step(state.x, state.y, 2.0, DELTA, left)
		left -= DELTA
	var next := steering.step(state.x, state.y, -2.0, DELTA, left)
	assert_lt(absf(next.x - state.x), 0.1 * absf(-2.0 - state.x))


func test_step_carries_the_velocity_it_is_given() -> void:
	var from_rest := steering.step(0.0, 0.0, 2.0, DELTA, 1.0)
	var moving := steering.step(0.0, 3.0, 2.0, DELTA, 1.0)
	assert_gt(moving.x, from_rest.x)
	assert_gt(moving.y, from_rest.y)


func test_step_moves_toward_a_target_below() -> void:
	var states := _run(0.0, -2.0, 0.5)
	assert_lt(states[0].x, 0.0)
	assert_eq(states[-1].x, -2.0)


func test_step_snaps_when_time_left_is_at_most_delta() -> void:
	var result := steering.step(0.0, 3.0, 5.0, DELTA, DELTA)
	assert_eq(result, Vector2(5.0, 0.0))


func test_step_returns_the_target_when_already_there() -> void:
	assert_eq(steering.step(1.0, 0.5, 1.0, DELTA, 1.0), Vector2(1.0, 0.0))


func test_step_with_a_nan_returns_the_inputs_unchanged_and_reports() -> void:
	var result := steering.step(1.0, 0.5, NAN, DELTA, 1.0)
	assert_eq(result, Vector2(1.0, 0.5))
	assert_push_error_count(1)


func test_landing_with_a_nan_or_infinite_input_is_null_and_reports() -> void:
	var platform := _platform(0.0, 0.0, 1.0)
	assert_null(steering.landing(Vector3(NAN, 2, 0), 0.0, 0.0, RISE, FALL, [platform]))
	assert_null(steering.landing(Vector3(0, 2, 0), INF, 0.0, RISE, FALL, [platform]))
	assert_push_error_count(2)


func test_dodge_with_a_nan_input_is_null_and_reports() -> void:
	var platform := _platform(0.0, 2.0, 3.0)
	assert_null(steering.dodge(Vector3(0, 1, 0), 10.0, NAN, RISE, [platform], 0.0))
	assert_push_error_count(1)


func test_empty_footprints_give_null() -> void:
	assert_null(steering.landing(Vector3(0, 2, 0), 0.0, 0.0, RISE, FALL, []))
	assert_null(steering.dodge(Vector3(0, 2, 0), 5.0, 0.0, RISE, [], 0.0))
	assert_push_error_count(0)
