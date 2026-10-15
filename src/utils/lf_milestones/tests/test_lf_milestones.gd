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
