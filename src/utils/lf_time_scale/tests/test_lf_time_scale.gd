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


func test_reset_without_a_pulse_leaves_the_speed_alone() -> void:
	Engine.time_scale = 2.0
	LFTimeScale.reset()
	assert_eq(Engine.time_scale, 2.0)
	assert_false(LFTimeScale.is_active())


func test_a_negative_length_ends_at_once() -> void:
	LFTimeScale.pulse(get_tree(), 0.3, -1.0)
	await wait_seconds(0.1)
	assert_eq(Engine.time_scale, 1.0)
	assert_false(LFTimeScale.is_active())


func test_the_taken_over_pulse_end_does_not_cut_the_new_one_short() -> void:
	LFTimeScale.pulse(get_tree(), 0.5, 0.05)
	LFTimeScale.pulse(get_tree(), 0.2, 0.4)
	await wait_seconds(0.04)
	assert_eq(Engine.time_scale, 0.2)
	assert_true(LFTimeScale.is_active())


func test_a_fast_forward_pulse_is_allowed() -> void:
	LFTimeScale.pulse(get_tree(), 2.0, 5.0)
	assert_eq(Engine.time_scale, 2.0)


# A second SceneTree cannot be created and freed inside a running GUT test, so the root's tree_exiting signal is not
# emitted for real (that would hit every other listener). The test checks the listener is attached for the pulse, calls
# it as the signal would, and checks it is detached afterwards. It does not cover a real tree being freed.
func test_the_tree_exiting_listener_ends_the_pulse() -> void:
	Engine.time_scale = 1.5
	LFTimeScale.pulse(get_tree(), 0.2, 5.0)
	var exiting: Signal = get_tree().root.tree_exiting
	var listeners := exiting.get_connections().filter(func(c: Dictionary) -> bool: return c['callable'].get_method() == &'_on_tree_exiting')
	assert_eq(listeners.size(), 1, 'one listener while the pulse is on')
	(listeners[0]['callable'] as Callable).call()
	assert_eq(Engine.time_scale, 1.5)
	assert_false(LFTimeScale.is_active())
	var left := exiting.get_connections().filter(func(c: Dictionary) -> bool: return c['callable'].get_method() == &'_on_tree_exiting')
	assert_eq(left.size(), 0, 'listener removed once the pulse is over')


func test_repeated_pulses_keep_a_single_listener() -> void:
	LFTimeScale.pulse(get_tree(), 0.5, 5.0)
	LFTimeScale.pulse(get_tree(), 0.4, 5.0)
	var listeners := get_tree().root.tree_exiting.get_connections().filter(func(c: Dictionary) -> bool: return c['callable'].get_method() == &'_on_tree_exiting')
	assert_eq(listeners.size(), 1)
