extends GutTest


func after_each() -> void:
	LFTimeScale.reset()
	Engine.time_scale = 1.0


func test_a_pulse_slows_the_game_then_restores_it() -> void:
	LFTimeScale.pulse(get_tree(), 0.25, 0.05)
	assert_eq(Engine.time_scale, 0.25)
	assert_true(LFTimeScale.is_active())
	await wait_seconds(0.2)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(LFTimeScale.is_active())


func test_a_second_pulse_takes_over_and_the_first_speed_comes_back() -> void:
	Engine.time_scale = 1.5
	LFTimeScale.pulse(get_tree(), 0.5, 0.3)
	LFTimeScale.pulse(get_tree(), 0.2, 0.05)
	assert_eq(Engine.time_scale, 0.2)
	await wait_seconds(0.1)
	assert_eq(Engine.time_scale, 1.5, 'the speed from before the first pulse is back')


func test_reset_ends_a_pulse_at_once() -> void:
	LFTimeScale.pulse(get_tree(), 0.3, 5.0)
	LFTimeScale.reset()
	assert_eq(Engine.time_scale, 1.0)


func test_a_scale_of_zero_is_lifted_to_the_minimum() -> void:
	LFTimeScale.pulse(get_tree(), 0.0, 0.05)
	assert_eq(Engine.time_scale, LFTimeScale.MIN_SCALE)


func test_a_null_tree_does_nothing() -> void:
	LFTimeScale.pulse(null, 0.1, 1.0)
	assert_eq(Engine.time_scale, 1.0)
