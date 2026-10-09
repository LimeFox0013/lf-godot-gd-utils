extends GutTest

## Real visibility is not computed in a headless run: nothing is drawn, so the notifier
## never emits and `frame_post_draw` never fires. The tests emit `screen_exited`/
## `screen_entered` directly, stand in for the renderer by emitting
## `RenderingServer.frame_post_draw`, and substitute visibility by overriding
## `_is_on_screen_now()`.

## Most game time `_wait_for_calls` waits for the expected reports, in seconds.
const WAIT_LIMIT_SECONDS := 3.0
## The documented default `delay`, in seconds.
const EXPECTED_DEFAULT_DELAY := 1.0
## The documented default `max_timeout`, in seconds.
const EXPECTED_DEFAULT_MAX_TIMEOUT := 300.0


class ProbeLeave3D extends LFViewportLeave3D:
	var on_screen := true

	func _is_on_screen_now() -> bool:
		return on_screen


var calls: Array[int] = [0]


func before_each():
	calls = [0]


func _count() -> void:
	calls[0] += 1


## Waits process frames until `expected` reports arrived or `WAIT_LIMIT_SECONDS` of
## process time (the time the timers count) went by.
func _wait_for_calls(expected: int) -> void:
	var elapsed := 0.0
	while calls[0] < expected and elapsed < WAIT_LIMIT_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## Waits process frames until timers have advanced by at least `seconds` of process
## time. (`process_frame` fires before the frame's nodes process, so one more frame lets
## the last counted delta reach them.)
func _advance_game_time(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await get_tree().process_frame


func _frame_drawn() -> void:
	RenderingServer.frame_post_draw.emit()
	await wait_process_frames(2)


func _probe(delay: float, max_timeout: float, on_screen: bool) -> ProbeLeave3D:
	var notifier := ProbeLeave3D.new(_count, delay, max_timeout)
	notifier.on_screen = on_screen
	return add_child_autofree(notifier)


func test_it_is_a_3d_visibility_notifier():
	var notifier := _probe(1.0, 0, true)
	assert_true(notifier is VisibleOnScreenNotifier3D)


func test_disabled_by_default_ignores_screen_exits():
	var notifier := _probe(0.02, 0, false)
	notifier.screen_exited.emit()
	assert_true(notifier.timer.is_stopped())


func test_an_exit_fires_the_callback_and_the_signal_after_the_delay():
	var notifier := _probe(0.02, 0, true)
	notifier.left_viewport.connect(_count)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await _wait_for_calls(2)

	assert_eq(calls[0], 2)


func test_re_entering_cancels_the_pending_delay():
	var notifier := _probe(0.05, 0, true)
	notifier.set_disabled(false)
	notifier.screen_exited.emit()
	notifier.screen_entered.emit()
	await _advance_game_time(0.2)

	assert_true(notifier.timer.is_stopped())
	assert_eq(calls[0], 0, "the delay passed without a report")


func test_a_node_already_off_screen_when_enabled_starts_the_delay():
	var notifier := _probe(30.0, 0, false)

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_false(notifier.timer.is_stopped())


func test_a_node_on_screen_when_enabled_waits_for_an_exit():
	var notifier := _probe(30.0, 0, true)

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_true(notifier.timer.is_stopped())


func test_a_zero_delay_fires_on_the_exit_itself():
	var notifier := _probe(0.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_the_max_timeout_fires_once_and_counts_only_enabled_time():
	var notifier := _probe(100.0, 0.02, true)
	assert_true(notifier.max_timer.paused, "starts disabled")
	await _advance_game_time(0.2)
	assert_eq(calls[0], 0, "ten fallback periods of disabled time report nothing")

	notifier.disabled = false
	await _wait_for_calls(1)
	await _advance_game_time(0.2)

	assert_eq(calls[0], 1, "ten fallback periods later, still one report")
	assert_true(notifier.max_timer.is_stopped())


func test_a_zero_or_negative_max_timeout_means_no_fallback():
	assert_null(_probe(1.0, 0.0, true).max_timer)
	assert_null(_probe(1.0, -5.0, true).max_timer)


func test_writing_the_disabled_property_pauses_and_resumes_everything():
	var notifier := _probe(10.0, 50.0, true)

	notifier.disabled = false
	notifier.screen_exited.emit()
	assert_false(notifier.max_timer.paused)
	assert_false(notifier.timer.is_stopped())

	notifier.disabled = true
	assert_true(notifier.max_timer.paused)
	assert_true(notifier.timer.is_stopped())


func test_it_can_be_created_without_arguments():
	var notifier: LFViewportLeave3D = add_child_autofree(LFViewportLeave3D.new())
	assert_eq(notifier.delay, EXPECTED_DEFAULT_DELAY)
	assert_eq(notifier.max_timeout, EXPECTED_DEFAULT_MAX_TIMEOUT)
	assert_eq(LFViewportLeave3D.DEFAULT_DELAY, EXPECTED_DEFAULT_DELAY)
	assert_eq(LFViewportLeave3D.DEFAULT_MAX_TIMEOUT, EXPECTED_DEFAULT_MAX_TIMEOUT)
	assert_true(notifier.disabled)


func test_add_to_parents_the_notifier_and_returns_it_for_chaining():
	var parent: Node3D = add_child_autofree(Node3D.new())
	var notifier := LFViewportLeave3D.new(_count, 1.0, 0)

	var returned := notifier.add_to(parent)

	assert_same(returned, notifier)
	assert_same(notifier.get_parent(), parent)


func test_setting_delay_and_max_timeout_later_retimes_or_removes_the_timers():
	var notifier := _probe(1.0, 0.0, true)

	notifier.delay = 2.5
	notifier.max_timeout = 40.0
	assert_eq(notifier.timer.wait_time, 2.5)
	assert_eq(notifier.max_timer.wait_time, 40.0)
	assert_true(notifier.max_timer.paused, "only enabled time counts")

	notifier.max_timeout = 0.0
	assert_null(notifier.max_timer)


func test_a_callback_on_a_freed_object_is_skipped():
	var target := Node.new()
	var notifier: LFViewportLeave3D = add_child_autofree(LFViewportLeave3D.new(target.queue_free, 0.0, 0))
	notifier.left_viewport.connect(_count)
	notifier.set_disabled(false)
	target.free()

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1, "the signal still fires; the dead callback is not called")


func test_a_callback_assigned_after_creation_is_called():
	var notifier: LFViewportLeave3D = add_child_autofree(LFViewportLeave3D.new())
	notifier.delay = 0.0
	notifier.callback = _count
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_lowering_max_timeout_while_it_counts_applies_the_new_limit():
	var notifier := _probe(100.0, 300.0, true)
	notifier.set_disabled(false)
	await wait_process_frames(2)

	notifier.max_timeout = 0.05
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_entering_the_tree_enabled_and_off_screen_starts_the_delay():
	var notifier := ProbeLeave3D.new(_count, 30.0, 0)
	notifier.on_screen = false
	notifier.disabled = false
	add_child_autofree(notifier)

	await _frame_drawn()

	assert_false(notifier.timer.is_stopped(), "the check when it enters the tree finds it off-screen")


func test_a_node_that_left_while_disabled_is_reported_once_enabled():
	var notifier := _probe(0.02, 0, true)
	notifier.on_screen = false
	notifier.screen_exited.emit() # ignored while disabled

	notifier.set_disabled(false)
	await _frame_drawn()
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_its_timers_are_internal_children():
	var notifier := _probe(1.0, 30.0, true)
	assert_eq(notifier.get_child_count(), 0, "nothing shows in get_children()")
	assert_true(notifier.timer.get_parent() == notifier)
	assert_true(notifier.max_timer.get_parent() == notifier)


func test_one_departure_is_reported_once_and_stands_the_max_timeout_down():
	var notifier := _probe(0.02, 50.0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await _wait_for_calls(1)
	await wait_process_frames(2)

	assert_eq(calls[0], 1)
	assert_true(notifier.max_timer.is_stopped(), "the fallback does not report the same departure again")


func test_disabling_before_a_zero_delay_report_lands_cancels_it():
	var notifier := _probe(0.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	notifier.set_disabled(true)
	await wait_process_frames(2)

	assert_eq(calls[0], 0)


func test_enabling_an_enabled_notifier_does_not_restart_the_delay():
	var notifier := _probe(10.0, 0, true)
	notifier.set_disabled(false)
	notifier.screen_exited.emit()
	await wait_process_frames(3)
	var left := notifier.timer.time_left
	assert_lt(left, 10.0, "precondition: the delay is counting")

	notifier.set_disabled(false)

	assert_almost_eq(notifier.timer.time_left, left, 0.0001, "no frame ran in between")
	assert_lt(notifier.timer.time_left, 10.0)


func test_a_negative_delay_reports_on_the_exit_itself():
	var notifier := _probe(-1.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_a_notifier_freed_before_its_zero_delay_report_lands_reports_nothing():
	var notifier := ProbeLeave3D.new(_count, 0.0, 0)
	add_child(notifier)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	notifier.free()
	await wait_process_frames(2)

	assert_eq(calls[0], 0)


func test_a_nan_delay_or_max_timeout_is_rejected_and_the_value_is_kept():
	var notifier: LFViewportLeave3D = autofree(LFViewportLeave3D.new(Callable(), 2.0, 10.0))
	notifier.delay = NAN
	notifier.max_timeout = NAN
	assert_push_error_count(2)
	assert_eq([notifier.delay, notifier.max_timeout], [2.0, 10.0])
