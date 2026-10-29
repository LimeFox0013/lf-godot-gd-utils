extends GutTest

var m: LFMilestones


func before_each():
	m = LFMilestones.new(50.0, 5)


func test_nothing_below_the_first_step():
	assert_eq(m.advance(49.9).size(), 0)
	assert_eq(m.advance(-10.0).size(), 0)


func test_the_first_crossing_is_reported():
	var got := m.advance(50.0)
	assert_eq(got.size(), 1)
	assert_eq(got[0].value, 50.0)
	assert_eq(got[0].number, 1)
	assert_false(got[0].big)


func test_falling_back_and_rising_again_reports_nothing():
	m.advance(120.0)
	m.advance(10.0)
	assert_eq(m.advance(120.0).size(), 0)
	assert_eq(m.advance(160.0).size(), 1)


func test_several_crossed_in_one_call_come_in_order():
	var got := m.advance(160.0)
	assert_eq(got.map(func(d): return d.value), [50.0, 100.0, 150.0])


func test_every_nth_is_big():
	var got := m.advance(260.0)
	assert_eq(got.size(), 5)
	assert_true(got[4].big)
	assert_false(got[3].big)


func test_reset_forgets():
	m.advance(120.0)
	m.reset()
	assert_eq(m.advance(60.0).size(), 1)


func test_bad_arguments_use_defaults():
	var bad := LFMilestones.new(0.0, 0)
	assert_push_error_count(2)
	assert_eq(bad.step, LFMilestones.DEFAULT_STEP)


func test_a_non_finite_value_is_reported_and_ignored():
	assert_eq(m.advance(NAN).size(), 0)
	assert_push_error_count(1)


func test_reached_tracks_the_highest_number_and_reset_clears_it():
	assert_eq(m.reached, 0)
	m.advance(120.0)
	assert_eq(m.reached, 2)
	m.advance(10.0)
	assert_eq(m.reached, 2)
	m.reset()
	assert_eq(m.reached, 0)


func test_step_is_exposed():
	assert_eq(m.step, 50.0)


func test_defaults_are_used_without_arguments():
	var d := LFMilestones.new()
	assert_eq(d.step, 10.0)
	var got := d.advance(50.0)
	assert_eq(got.size(), 5)
	assert_true(got[4].big)


func test_big_every_below_one_uses_the_default():
	var bad := LFMilestones.new(10.0, 0)
	assert_push_error_count(1)
	var got := bad.advance(50.0)
	assert_true(got[4].big)
	assert_false(got[3].big)


func test_non_finite_step_uses_the_default():
	var bad := LFMilestones.new(INF)
	assert_push_error_count(1)
	assert_eq(bad.step, LFMilestones.DEFAULT_STEP)


func test_infinite_value_is_ignored():
	assert_eq(m.advance(INF).size(), 0)
	assert_push_error_count(1)
	assert_eq(m.reached, 0)


func test_entries_carry_value_number_and_big():
	var got := m.advance(100.0)
	assert_eq(got[1].number, 2)
	assert_eq(got[1].value, 100.0)
	assert_eq(got[1].keys().size(), 3)


func test_an_exact_multiple_counts():
	assert_eq(m.advance(100.0).size(), 2)


func test_huge_jump_is_refused_and_changes_nothing():
	assert_eq(m.advance(1e18).size(), 0)
	assert_push_error_count(1)
	assert_eq(m.reached, 0)
	assert_eq(m.advance(100.0).size(), 2)


func test_jump_of_exactly_the_cap_is_allowed():
	assert_eq(m.advance(50.0 * LFMilestones.MAX_PER_CALL).size(), LFMilestones.MAX_PER_CALL)


func test_jump_one_past_the_cap_is_refused():
	assert_eq(m.advance(50.0 * (LFMilestones.MAX_PER_CALL + 1)).size(), 0)
	assert_push_error_count(1)


func test_cap_counts_from_what_is_already_reached():
	m.advance(500.0)
	assert_eq(m.advance(50.0 * (10 + LFMilestones.MAX_PER_CALL)).size(), LFMilestones.MAX_PER_CALL)
