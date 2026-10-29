extends GutTest

var countdown: LFCountdown
var ticks: Array[float]
var finished_count: int


func before_each():
	countdown = LFCountdown.new(5.0)
	ticks = []
	finished_count = 0
	countdown.ticked.connect(func(remaining: float): ticks.append(remaining))
	countdown.finished.connect(func(): finished_count += 1)


func test_a_new_countdown_is_stopped_with_the_full_time_left():
	assert_eq(countdown.state, LFCountdown.State.STOPPED)
	assert_eq(countdown.remaining, 5.0)
	assert_eq(countdown.progress(), 0.0)


func test_tick_does_nothing_until_started():
	assert_false(countdown.tick(3.0))
	assert_eq(countdown.remaining, 5.0)
	assert_eq(ticks, [] as Array[float])


func test_it_emits_ticked_for_each_whole_second():
	countdown.start()
	countdown.tick(0.9)
	assert_eq(ticks, [] as Array[float])
	countdown.tick(0.2)
	assert_eq(ticks, [4.0] as Array[float])
	assert_almost_eq(countdown.remaining, 3.9, 0.0001)


func test_a_long_delta_emits_every_covered_second_in_order_with_their_remaining():
	countdown.start()
	countdown.tick(3.5)
	assert_eq(ticks, [4.0, 3.0, 2.0] as Array[float])


func test_it_finishes_at_zero_with_the_last_tick_first():
	countdown.start()
	assert_false(countdown.tick(4.0))
	assert_true(countdown.tick(1.0))
	assert_eq(ticks, [4.0, 3.0, 2.0, 1.0, 0.0] as Array[float])
	assert_eq(finished_count, 1)
	assert_true(countdown.is_finished())
	assert_eq(countdown.remaining, 0.0)
	assert_eq(countdown.progress(), 1.0)


func test_overshoot_is_dropped_and_a_finished_countdown_ignores_ticks():
	countdown.start()
	assert_true(countdown.tick(100.0))
	assert_eq(ticks.size(), 5)
	assert_false(countdown.tick(1.0))
	assert_eq(finished_count, 1)


func test_many_small_deltas_sum_without_drift():
	countdown = LFCountdown.new(1.0, 0.1)
	var count := [0]
	countdown.ticked.connect(func(_r): count[0] += 1)
	countdown.start()
	for i in 10:
		countdown.tick(0.1)
	assert_eq(count[0], 10)
	assert_true(countdown.is_finished())


func test_pause_holds_and_resume_continues():
	countdown.start()
	countdown.tick(1.5)
	countdown.pause()
	assert_true(countdown.is_paused())
	countdown.tick(10.0)
	assert_almost_eq(countdown.remaining, 3.5, 0.0001)
	countdown.resume()
	countdown.tick(0.5)
	assert_eq(ticks, [4.0, 3.0] as Array[float])


func test_start_while_paused_resumes_and_while_running_does_nothing():
	countdown.start()
	countdown.tick(2.0)
	countdown.start()
	assert_almost_eq(countdown.remaining, 3.0, 0.0001)
	countdown.pause()
	countdown.start()
	assert_true(countdown.is_running())
	assert_almost_eq(countdown.remaining, 3.0, 0.0001)


func test_stop_restores_the_full_time_without_signals():
	countdown.start()
	countdown.tick(2.5)
	countdown.stop()
	assert_eq(countdown.state, LFCountdown.State.STOPPED)
	assert_eq(countdown.remaining, 5.0)
	assert_eq(finished_count, 0)


func test_start_after_finishing_begins_again():
	countdown.start()
	countdown.tick(5.0)
	countdown.start()
	assert_true(countdown.is_running())
	assert_eq(countdown.remaining, 5.0)
	ticks.clear()
	countdown.tick(1.0)
	assert_eq(ticks, [4.0] as Array[float])


func test_restart_starts_over_from_any_state():
	countdown.start()
	countdown.tick(3.0)
	countdown.pause()
	countdown.restart()
	assert_true(countdown.is_running())
	assert_eq(countdown.remaining, 5.0)


func test_a_handler_that_restarts_ends_the_tick_in_progress():
	countdown.ticked.connect(func(_r): countdown.restart())
	countdown.start()
	countdown.tick(3.0)
	assert_eq(ticks, [4.0] as Array[float], 'one tick, then the call ended')
	assert_eq(countdown.remaining, 5.0)
	assert_eq(finished_count, 0)


func test_negative_and_non_finite_deltas_change_nothing():
	countdown.start()
	countdown.tick(-1.0)
	countdown.tick(NAN)
	countdown.tick(INF)
	assert_eq(countdown.remaining, 5.0)


func test_a_custom_tick_interval():
	countdown = LFCountdown.new(10.0, 2.5)
	countdown.ticked.connect(func(remaining: float): ticks.append(remaining))
	countdown.start()
	countdown.tick(5.0)
	assert_eq(ticks, [7.5, 5.0] as Array[float])


func test_text_uses_the_clock_format_and_rounds_up():
	countdown = LFCountdown.new(125.0)
	assert_eq(countdown.text(), '2:05')
	countdown.start()
	countdown.tick(0.5)
	assert_eq(countdown.text(), '2:05')
	assert_eq(countdown.text(false), '2:04')
	countdown.tick(200.0)
	assert_eq(countdown.text(), '0:00')


func test_invalid_duration_and_interval_are_reported_and_ignored():
	for bad in [NAN, 0.0, -1.0, INF]:
		countdown.duration = bad
	countdown.tick_interval = 0.0
	countdown.tick_interval = NAN
	assert_push_error_count(6)
	assert_eq(countdown.duration, 5.0)
	assert_eq(countdown.tick_interval, LFCountdown.DEFAULT_TICK_INTERVAL_SECONDS)


func test_changing_the_duration_while_running_keeps_the_elapsed_time():
	countdown.start()
	countdown.tick(2.0)
	countdown.duration = 10.0
	assert_almost_eq(countdown.remaining, 8.0, 0.0001)
