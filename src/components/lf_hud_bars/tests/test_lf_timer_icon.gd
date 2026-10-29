extends GutTest


func test_set_fraction_clamps_to_zero_and_one():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())

	icon.set_fraction(0.4)
	assert_almost_eq(icon.fraction, 0.4, 0.001)
	icon.set_fraction(3.0)
	assert_eq(icon.fraction, 1.0)
	icon.set_fraction(-1.0)
	assert_eq(icon.fraction, 0.0)


func test_nan_is_reported_and_ignored():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	icon.set_fraction(0.5)

	icon.set_fraction(NAN)

	assert_push_error('NaN')
	assert_almost_eq(icon.fraction, 0.5, 0.001)


func test_the_fraction_property_sets_too():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())

	icon.fraction = 0.25

	assert_almost_eq(icon.value, 0.25, 0.001)


func test_icon_sets_both_textures():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	var texture := PlaceholderTexture2D.new()

	icon.icon = texture

	assert_eq(icon.texture_under, texture)
	assert_eq(icon.texture_progress, texture)


func test_tracking_a_running_timer_follows_time_left():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	var timer: Timer = add_child_autofree(Timer.new())
	timer.wait_time = 10.0
	timer.start()
	await wait_process_frames(1)

	icon.track(timer)

	assert_almost_eq(icon.fraction, timer.time_left / timer.wait_time, 0.01)
	assert_gt(icon.fraction, 0.9)
	timer.start(5.0)
	await wait_process_frames(2)
	assert_almost_eq(icon.fraction, 1.0, 0.05, 'time_left over wait_time (5 of 5)')


func test_a_stopped_timer_shows_stopped_fraction_and_finishes_once():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	icon.stopped_fraction = 0.0
	var timer: Timer = add_child_autofree(Timer.new())
	timer.wait_time = 10.0
	watch_signals(icon)

	icon.track(timer)
	await wait_process_frames(2)

	assert_eq(icon.fraction, 0.0)
	assert_signal_emit_count(icon, 'finished', 1)


func test_stop_tracking_keeps_the_fraction():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	var timer: Timer = add_child_autofree(Timer.new())
	timer.wait_time = 10.0
	timer.start()
	icon.track(timer)
	icon.stop_tracking()
	icon.set_fraction(0.3)

	await wait_process_frames(2)

	assert_almost_eq(icon.fraction, 0.3, 0.001)
	assert_null(icon.timer)


func test_a_freed_timer_ends_tracking():
	var icon: LFTimerIcon = add_child_autofree(LFTimerIcon.new())
	var timer := Timer.new()
	icon.track(timer)

	timer.free()
	await wait_process_frames(2)

	assert_null(icon.timer)
