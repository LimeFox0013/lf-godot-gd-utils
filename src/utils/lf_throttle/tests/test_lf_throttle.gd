extends GutTest

## Engine.time_scale and the tree's pause as they were before each test; after_each puts
## them back.
var _saved_time_scale := 1.0
var _saved_paused := false


func before_each():
	_saved_time_scale = Engine.time_scale
	_saved_paused = get_tree().paused


func after_each():
	Engine.time_scale = _saved_time_scale
	get_tree().paused = _saved_paused


## LFThrottle measures intervals in wall-clock ms, but a SceneTreeTimer advances by
## frame delta, which can jump ahead right after startup. Waiting on wall-clock time
## keeps these tests deterministic when the file runs on its own.
func _wait_wall_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	# A frame that overshoots the deadline resumes this wait before the engine runs the
	# timers that came due in it, so give them two more frames.
	await get_tree().process_frame
	await get_tree().process_frame


func test_no_two_leading_executions_occur_closer_than_the_interval():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 40, true, false)

	throttled.call("a") # leading edge — executes immediately
	throttled.call("b") # within the interval — must be swallowed
	assert_eq(calls, ["a"])

	await _wait_wall_ms(60) # past the interval
	throttled.call("c") # new leading edge
	assert_eq(calls, ["a", "c"])


func test_trailing_execution_fires_with_the_latest_args_after_the_interval():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 30, true, true)

	throttled.call("a")
	throttled.call("b") # latest args before the trailing fire
	assert_eq(calls, ["a"])

	# Waits for the trailing fire rather than a fixed time: a loaded machine runs it late.
	var deadline := Time.get_ticks_msec() + 3000
	while calls.size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert_eq(calls, ["a", "b"])


func test_a_single_call_with_leading_and_trailing_executes_exactly_once():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 30, true, true)

	throttled.call("a")
	await _wait_wall_ms(80)

	assert_eq(calls, ["a"], "the trailing edge has nothing new to deliver after an isolated call")


func test_a_trailing_window_does_not_delay_the_next_leading_call_past_the_interval():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 40, true, true)

	throttled.call("a")
	await _wait_wall_ms(60) # one full interval since "a", nothing pending
	throttled.call("b")

	assert_eq(calls, ["a", "b"], "a call more than one interval after the last execution must lead")


func test_trailing_only_defers_the_first_call_to_the_end_of_the_interval():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 30, false, true)

	throttled.call("a")
	assert_eq(calls, [])
	await _wait_wall_ms(60)

	assert_eq(calls, ["a"])




func test_the_trailing_wait_is_real_time_like_the_window():
	var calls := []
	var throttled = LFThrottle.fn(func(v): calls.append(v), 30, false, true)
	Engine.time_scale = 0.05 # a scaled 30 ms wait would take 600 ms

	throttled.call("a")
	await _wait_wall_ms(150)

	assert_eq(calls, ["a"])


func test_neither_leading_nor_trailing_is_reported_and_never_runs():
	var calls := []
	var throttled := LFThrottle.fn(func(): calls.append(1), 30, false, false)
	assert_push_error("leading and trailing are both false")

	throttled.call()
	await _wait_wall_ms(80)

	assert_eq(calls, [], 'reported, not asserted: the throttle exists and never runs')


func test_called_every_frame_it_never_runs_twice_within_an_interval():
	var times := []
	var throttled = LFThrottle.fn(func(): times.append(Time.get_ticks_msec()), 30, true, true)
	var until := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < until:
		throttled.call()
		await get_tree().process_frame
	await _wait_wall_ms(60)
	for i in range(1, times.size()):
		assert_gte(times[i] - times[i - 1], 29, "executions %d and %d" % [i - 1, i])


func test_an_instance_can_cancel_a_pending_trailing_call():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	assert_true(throttle.is_pending())
	throttle.cancel()
	assert_false(throttle.is_pending())
	await _wait_wall_ms(60)
	assert_eq(calls, ["a"])


func test_flush_runs_the_pending_call_now():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 1000, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	throttle.flush()
	assert_eq(calls, ["a", "b"])
	assert_false(throttle.is_pending())
	await _wait_wall_ms(30)
	assert_eq(calls, ["a", "b"], "the cancelled trailing timer does not run it again")


func test_a_freed_target_is_skipped_without_an_error():
	var target := Counter.new()
	var throttle := LFThrottle.new(target.bump, 20, false, true)
	throttle.trigger()
	target.free()
	await _wait_wall_ms(50)
	assert_false(throttle.is_pending())


class Counter:
	extends Object
	var count := 0
	func bump() -> void:
		count += 1


func test_with_trailing_off_a_call_inside_the_window_is_dropped():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 1000, true, false)
	throttle.trigger("a")
	throttle.trigger("b")
	assert_false(throttle.is_pending(), "nothing waits: the call was dropped")
	throttle.flush()
	assert_eq(calls, ["a"], "flush has nothing to run")
	assert_eq(throttle._args, [], "the dropped call's arguments are not kept")


func test_the_trailing_wait_keeps_running_while_the_tree_is_paused():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	get_tree().paused = true
	await _wait_wall_ms(120)
	get_tree().paused = false
	assert_eq(calls, ["a", "b"])


func test_a_trailing_wait_outlived_by_a_leading_run_waits_out_the_new_window():
	var calls := []
	var times := {}
	var throttle := LFThrottle.new(func(v):
		calls.append(v)
		times[v] = Time.get_ticks_msec(), 60, true, true)
	throttle.trigger("a")
	throttle.trigger("x") # schedules a trailing wait ending with a's window
	OS.delay_msec(80) # a's window ends without a frame, so that wait has not fired yet
	throttle.trigger("b") # leads and opens a new window
	throttle.trigger("c") # pending; the old wait is still the scheduled one
	assert_eq(calls, ["a", "b"])
	await get_tree().process_frame
	await get_tree().process_frame
	if Time.get_ticks_msec() - times["b"] < 60: # unless two frames outlasted b's window
		assert_eq(calls, ["a", "b"], "the stale wait does not run c inside b's window")
	await _wait_wall_ms(150)
	assert_eq(calls, ["a", "b", "c"])
	assert_gte(times["c"] - times["b"], 59, "c runs a full interval after b")


func test_a_longer_interval_set_while_waiting_is_waited_out():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	throttle.interval_ms = 200
	await _wait_wall_ms(90)
	assert_eq(calls, ["a"], "the wait scheduled for 30 ms re-schedules for the new window")
	await _wait_wall_ms(200)
	assert_eq(calls, ["a", "b"])


func test_the_edges_can_be_changed_after_construction():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, false)
	assert_true(throttle.leading)
	assert_false(throttle.trailing)
	throttle.trigger("a")
	throttle.trigger("b")
	assert_false(throttle.is_pending(), "leading only: the call inside the window is dropped")
	throttle.trailing = true
	throttle.trigger("c")
	assert_true(throttle.is_pending(), "with trailing switched on, it waits for the window end")
	throttle.flush()
	assert_eq(calls, ["a", "c"])


func test_switching_both_edges_off_later_silently_disables_it():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, true)
	throttle.leading = false
	throttle.trailing = false
	throttle.trigger("a")
	assert_false(throttle.is_pending())
	await _wait_wall_ms(60)
	assert_eq(calls, [], "nothing runs")
	assert_engine_error_count(0)
	throttle.leading = true
	throttle.trigger("b")
	assert_eq(calls, ["b"], "switching an edge back on brings it back")


func test_flush_opens_a_new_window():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 1000, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	throttle.flush()
	throttle.trigger("c")
	assert_eq(calls, ["a", "b"], "c falls inside the window flush opened, so it does not lead")
	assert_true(throttle.is_pending())
	throttle.cancel()


func test_flush_with_nothing_waiting_does_nothing():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 1000, true, true)
	throttle.flush()
	throttle.trigger("a")
	assert_eq(calls, ["a"], "flush did not open a window, so a still leads")


func test_a_leading_run_clears_a_pending_call():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 40, true, true)
	throttle.trigger("a")
	throttle.trigger("stale")
	OS.delay_msec(60) # the window ends without a frame, so the trailing wait has not fired
	throttle.trigger("b") # opens a new window and leads
	assert_false(throttle.is_pending(), "the stale call no longer waits")
	await _wait_wall_ms(120)
	assert_eq(calls, ["a", "b"])


func test_fn_passes_every_argument_through():
	var calls := []
	var throttled := LFThrottle.fn(func(a, b, c): calls.append([a, b, c]), 30)
	throttled.call(1, "two", [3])
	assert_eq(calls, [[1, "two", [3]]])


func test_the_default_interval_is_one_60_fps_frame():
	assert_almost_eq(LFThrottle.DEFAULT_INTERVAL_MS, 16.667, 0.001)
	var throttle := LFThrottle.new(func(): pass)
	assert_eq(throttle.interval_ms, LFThrottle.DEFAULT_INTERVAL_MS)
	assert_true(throttle.leading)
	assert_false(throttle.trailing)


func test_a_dropped_throttle_never_runs_its_waiting_call():
	var calls := []
	var throttle := LFThrottle.new(func(v): calls.append(v), 30, true, true)
	throttle.trigger("a")
	throttle.trigger("b")
	var ref: WeakRef = weakref(throttle)
	throttle = null
	await _wait_wall_ms(90)
	assert_eq(calls, ["a"], "the waiting call died with the throttle")
	assert_null(ref.get_ref(), "nothing kept the throttle alive")


func test_a_freed_target_on_the_leading_edge_is_skipped_without_an_error():
	var target := Counter.new()
	var throttle := LFThrottle.new(target.bump, 20)
	target.free()
	throttle.trigger()
	assert_engine_error_count(0)


func test_a_nan_interval_is_rejected_and_the_value_is_kept():
	var throttle := LFThrottle.new(func(): pass, 100.0)
	throttle.interval_ms = NAN
	assert_push_error('NaN')
	assert_eq(throttle.interval_ms, 100.0)
	assert_eq(LFThrottle.new(func(): pass, NAN).interval_ms, LFThrottle.DEFAULT_INTERVAL_MS)
	assert_push_error_count(2)
