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


func test_a_call_before_the_delay_elapses_cancels_the_previous_pending_call():
	var calls := []
	var debounced = LFDebounce.fn(func(v): calls.append(v), 600) # long, so a stalled frame between the calls can't expire it
	# Start on a frame boundary: a SceneTreeTimer's first tick counts the whole
	# delta of a frame that began before it was created, so a long preceding
	# frame could otherwise fire both timers together.
	await LFAwait.next_tick

	debounced.call("first")
	await LFUtils.timeout(20) # well within the window
	debounced.call("second")
	await LFUtils.timeout(800) # past the window from the second call

	assert_eq(calls, ["second"])


func test_a_call_after_the_delay_elapses_executes_independently():
	var calls := []
	var debounced = LFDebounce.fn(func(v): calls.append(v), 20)
	await LFAwait.next_tick

	debounced.call("first")
	await LFUtils.timeout(40) # past the window — "first" should have fired
	debounced.call("second")
	await LFUtils.timeout(40)

	assert_eq(calls, ["first", "second"])




func _wait_wall_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	# A frame that overshoots the deadline resumes this wait before the engine runs the
	# timers that came due in it, so give them two more frames.
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_last_calls_arguments_run_once_after_the_delay():
	var calls := []
	var debounced = LFDebounce.fn(func(a, b): calls.append([a, b]), 30)
	await LFAwait.next_tick

	debounced.call(1, "x")
	debounced.call(2, "y")
	debounced.call(3, "z")
	assert_eq(calls, [], "nothing runs before the delay")
	await _wait_wall_ms(120)

	assert_eq(calls, [[3, "z"]])


func test_cancel_drops_the_pending_call():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(v), 30)

	debouncer.trigger("a")
	assert_true(debouncer.is_pending())
	debouncer.cancel()
	assert_false(debouncer.is_pending())
	await _wait_wall_ms(100)

	assert_eq(calls, [])


func test_flush_runs_the_pending_call_now_and_only_once():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(v), 30)

	debouncer.trigger("a")
	debouncer.trigger("b")
	debouncer.flush()
	assert_eq(calls, ["b"], "flush runs the latest call immediately")
	await _wait_wall_ms(100)

	assert_eq(calls, ["b"], "the flushed call does not run again when the delay ends")


func test_flush_with_nothing_pending_does_nothing():
	var calls := []
	var debouncer := LFDebounce.new(func(): calls.append(1), 30)

	debouncer.flush()

	assert_eq(calls, [])


func test_the_delay_is_real_time_and_ignores_the_engine_time_scale():
	var calls := []
	var debounced = LFDebounce.fn(func(v): calls.append(v), 40)
	await LFAwait.next_tick
	Engine.time_scale = 0.05 # a scaled 40 ms delay would take 800 ms

	debounced.call("a")
	await _wait_wall_ms(200)

	assert_eq(calls, ["a"])


func test_rapid_triggers_reuse_one_timer():
	var debouncer := LFDebounce.new(func(_v): pass, 50)
	debouncer.trigger(1)
	var timer := debouncer._timer
	for i in 20:
		debouncer.trigger(i)
	assert_true(is_same(debouncer._timer, timer), 'still the first timer, its wait restarted')


func test_the_arguments_are_released_once_it_has_run():
	var debouncer := LFDebounce.new(func(_v): pass, 20)
	debouncer.trigger(RefCounted.new())
	await _wait_wall_ms(60)
	assert_false(debouncer.is_pending())
	assert_eq(debouncer._args, [])


func test_a_freed_target_is_skipped_without_an_error():
	var target := Counter.new()
	var debouncer := LFDebounce.new(target.bump, 20)
	debouncer.trigger()
	target.free()
	await _wait_wall_ms(60)
	assert_false(debouncer.is_pending())


class Counter:
	extends Object
	var count := 0
	func bump() -> void:
		count += 1


func test_the_delay_keeps_running_while_the_tree_is_paused():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(v), 30)
	debouncer.trigger("a")
	get_tree().paused = true
	await _wait_wall_ms(120)
	get_tree().paused = false
	assert_eq(calls, ["a"])


func test_a_trigger_after_delay_ms_changed_waits_the_new_delay():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(v), 1000)
	await LFAwait.next_tick
	debouncer.trigger("a")
	debouncer.delay_ms = 20
	debouncer.trigger("b")
	await _wait_wall_ms(120)
	assert_eq(calls, ["b"], "the restarted wait uses the shorter delay")


func test_a_replaced_callback_is_the_one_that_runs():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(["old", v]), 20)
	await LFAwait.next_tick
	debouncer.trigger("a")
	debouncer.callback = func(v): calls.append(["new", v])
	await _wait_wall_ms(80)
	assert_eq(calls, [["new", "a"]], "the callback is read when the delay ends")


func test_the_default_delay_is_one_60_fps_frame():
	var debouncer := LFDebounce.new(func(): pass)
	assert_almost_eq(debouncer.delay_ms, 1000.0 / 60.0, 0.0001)
	assert_eq(LFDebounce.DEFAULT_DELAY_MS, 1000.0 / 60)


func test_a_trigger_after_cancel_schedules_again():
	var calls := []
	var debouncer := LFDebounce.new(func(v): calls.append(v), 20)
	debouncer.trigger("dropped")
	debouncer.cancel()

	debouncer.trigger("kept")
	assert_true(debouncer.is_pending())
	await _wait_wall_ms(80)

	assert_eq(calls, ["kept"])


func test_a_callback_that_triggers_again_schedules_a_new_run():
	var calls := []
	var holder := []
	var debouncer := LFDebounce.new(func(v):
		calls.append(v)
		if v == "first":
			holder[0].trigger("second"), 20)
	holder.append(debouncer)
	debouncer.trigger("first")
	await _wait_wall_ms(150)

	assert_eq(calls, ["first", "second"], "the run had already cleared its schedule, so the new trigger counts")
	assert_false(debouncer.is_pending())
	holder.clear() # break the debouncer -> callback -> holder cycle


func test_flush_runs_with_the_latest_arguments_and_clears_them():
	var calls := []
	var debouncer := LFDebounce.new(func(a, b): calls.append([a, b]), 1000)
	debouncer.trigger(1, 2)
	debouncer.trigger(3, 4)

	debouncer.flush()

	assert_eq(calls, [[3, 4]])
	assert_false(debouncer.is_pending())
	assert_eq(debouncer._args, [])


func test_a_nan_delay_is_rejected_and_the_value_is_kept():
	var debounce := LFDebounce.new(func(): pass, 100.0)
	debounce.delay_ms = NAN
	assert_push_error('NaN')
	assert_eq(debounce.delay_ms, 100.0)
	assert_eq(LFDebounce.new(func(): pass, NAN).delay_ms, LFDebounce.DEFAULT_DELAY_MS)
	assert_push_error_count(2)
