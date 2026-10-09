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


class ProbeLeave extends LFViewportLeave:
	var on_screen := true

	func _is_on_screen_now() -> bool:
		return on_screen


class Target extends Node:
	var calls := 0

	func hit() -> void:
		calls += 1


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


## Waits process frames until timers and tweens have advanced by at least `seconds` of
## process time, however fast or slow the frames come. (`process_frame` fires before the
## frame's nodes process, so one more frame lets the last counted delta reach them.)
func _advance_game_time(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await get_tree().process_frame


func _frame_drawn() -> void:
	RenderingServer.frame_post_draw.emit()
	await wait_process_frames(2)


func _probe(delay: float, max_timeout: float, on_screen: bool) -> ProbeLeave:
	var notifier := ProbeLeave.new(_count, delay, max_timeout)
	notifier.on_screen = on_screen
	return add_child_autofree(notifier)


func test_disabled_by_default_ignores_screen_exits():
	var notifier := _probe(0.02, 0, false)

	notifier.screen_exited.emit()

	assert_true(notifier.disabled)
	assert_true(notifier.timer.is_stopped())


func test_enabled_and_triggered_exit_fires_the_callback_after_the_delay():
	var notifier := _probe(0.02, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	assert_false(notifier.timer.is_stopped(), "the exit starts the delay")
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_re_entering_before_the_delay_elapses_cancels_the_pending_callback():
	var notifier := _probe(0.05, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	notifier.screen_entered.emit()
	await _advance_game_time(0.2)

	assert_true(notifier.timer.is_stopped())
	assert_eq(calls[0], 0, "the delay passed without a report")


func test_disabling_mid_delay_stops_the_pending_timer():
	var notifier := _probe(0.03, 0, true)
	notifier.set_disabled(false)
	notifier.screen_exited.emit()

	notifier.set_disabled(true)

	assert_true(notifier.timer.is_stopped())


func test_a_zero_delay_fires_on_the_exit_itself():
	var notifier := _probe(0.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	assert_eq(calls[0], 0, "the callback runs deferred, not inside the visibility signal")
	await wait_process_frames(2)

	assert_eq(calls[0], 1)
	assert_true(notifier.timer.is_stopped())


func test_a_negative_delay_fires_on_the_exit_like_zero():
	var notifier := _probe(-1.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_a_node_already_off_screen_when_enabled_starts_the_delay():
	var notifier := _probe(30.0, 0, false)
	await _frame_drawn()

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_false(notifier.timer.is_stopped(), "enabling while off-screen starts the delay")


func test_a_node_already_off_screen_when_enabled_fires_after_the_delay():
	var notifier := _probe(0.02, 0, false)
	await _frame_drawn()

	notifier.set_disabled(false)
	await _frame_drawn()
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_a_node_on_screen_when_enabled_waits_for_an_exit():
	var notifier := _probe(0.02, 0, true)

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_true(notifier.timer.is_stopped())


func test_an_exit_while_disabled_fires_once_enabled_while_still_off_screen():
	var notifier := _probe(0.02, 0, true)
	await _frame_drawn()
	notifier.on_screen = false
	notifier.screen_exited.emit() # ignored: disabled

	notifier.set_disabled(false)
	await _frame_drawn()
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_an_enabled_notifier_entering_the_tree_off_screen_fires_after_the_delay():
	var notifier := ProbeLeave.new(_count, 0.02, 0)
	notifier.on_screen = false
	notifier.set_disabled(false)
	add_child_autofree(notifier)

	await _frame_drawn()
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_visibility_is_not_judged_before_a_frame_is_drawn():
	var notifier := _probe(0.02, 0, false)

	notifier.set_disabled(false)
	await wait_process_frames(3)

	assert_true(notifier.timer.is_stopped(), "a frame must be drawn before the node counts as off-screen")


func test_re_enabling_while_the_delay_runs_does_not_restart_it():
	var notifier := _probe(10.0, 0, false)
	notifier.set_disabled(false)
	await _frame_drawn()
	notifier.timer.start(5.0)

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_almost_eq(notifier.timer.time_left, 5.0, 0.5)


func test_max_timeout_fires_the_callback_on_its_own_exactly_once():
	var notifier := _probe(100.0, 0.02, true)
	notifier.set_disabled(false)

	await _wait_for_calls(1)
	await _advance_game_time(0.2)

	assert_eq(calls[0], 1, "ten fallback periods later, still one report")
	assert_true(notifier.max_timer.is_stopped(), "the fallback is one-shot")
	assert_true(notifier.timer.is_stopped())


func test_the_max_timeout_does_not_run_while_the_notifier_starts_disabled():
	var notifier := _probe(100.0, 0.02, true)
	await _advance_game_time(0.2)

	assert_true(notifier.max_timer.paused)
	assert_eq(calls[0], 0, "ten fallback periods of disabled time report nothing")


func test_disabling_pauses_the_max_timeout_and_enabling_resumes_it():
	var notifier := _probe(100.0, 50.0, true)
	notifier.set_disabled(false)
	assert_false(notifier.max_timer.paused)

	notifier.set_disabled(true)
	assert_true(notifier.max_timer.paused)
	var left := notifier.max_timer.time_left

	notifier.set_disabled(false)
	assert_false(notifier.max_timer.paused)
	assert_almost_eq(notifier.max_timer.time_left, left, 0.5, "resumes where it left off")


func test_the_max_timeout_safety_net_stands_down_once_the_delay_path_fired():
	var notifier := _probe(0.02, 50.0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await _wait_for_calls(1)

	assert_true(notifier.max_timer.is_stopped(), "one exit must not be reported a second time by the fallback")


func test_the_delay_path_stands_down_once_the_max_timeout_fired():
	var notifier := _probe(50.0, 0.02, true)
	notifier.set_disabled(false)
	notifier.screen_exited.emit()

	await _wait_for_calls(1)

	assert_true(notifier.timer.is_stopped())


func test_a_zero_or_negative_max_timeout_means_no_fallback():
	var none := _probe(1.0, 0.0, true)
	var negative := _probe(1.0, -5.0, true)

	assert_null(none.max_timer)
	assert_null(negative.max_timer)


func test_setting_max_timeout_later_adds_or_removes_the_fallback():
	var notifier := _probe(1.0, 0.0, true)

	notifier.max_timeout = 40.0
	assert_not_null(notifier.max_timer)
	assert_eq(notifier.max_timer.wait_time, 40.0)
	assert_false(notifier.max_timer.is_stopped(), "added in the tree, the fallback starts counting")
	assert_true(notifier.max_timer.paused, "but only counts enabled time")

	notifier.max_timeout = 0.0
	assert_null(notifier.max_timer)


func test_setting_delay_later_changes_the_delay_timer():
	var notifier := _probe(1.0, 0.0, true)
	notifier.delay = 2.5
	assert_eq(notifier.timer.wait_time, 2.5)


func test_writing_the_disabled_property_pauses_and_resumes_everything():
	var notifier := _probe(10.0, 50.0, true)

	notifier.disabled = false
	assert_false(notifier.max_timer.paused, "enabling through the property resumes the fallback")
	notifier.screen_exited.emit()
	assert_false(notifier.timer.is_stopped())

	notifier.disabled = true
	assert_true(notifier.max_timer.paused)
	assert_true(notifier.timer.is_stopped())


func test_it_can_be_created_without_arguments():
	var notifier: LFViewportLeave = add_child_autofree(LFViewportLeave.new())
	assert_eq(notifier.delay, EXPECTED_DEFAULT_DELAY)
	assert_eq(notifier.max_timeout, EXPECTED_DEFAULT_MAX_TIMEOUT)
	assert_eq(LFViewportLeave.DEFAULT_DELAY, EXPECTED_DEFAULT_DELAY)
	assert_eq(LFViewportLeave.DEFAULT_MAX_TIMEOUT, EXPECTED_DEFAULT_MAX_TIMEOUT)
	assert_true(notifier.disabled)


func test_left_viewport_is_emitted_without_a_callback():
	var notifier: LFViewportLeave = add_child_autofree(LFViewportLeave.new())
	notifier.delay = 0.0
	notifier.left_viewport.connect(_count)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_the_callback_and_the_signal_both_run():
	var notifier := _probe(0.0, 0, true)
	notifier.left_viewport.connect(_count)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 2)


func test_a_callback_on_a_freed_object_is_skipped():
	var target := Target.new()
	var notifier: LFViewportLeave = add_child_autofree(LFViewportLeave.new(target.hit, 0.0, 0))
	notifier.left_viewport.connect(_count)
	notifier.set_disabled(false)
	target.free()

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1, "the signal still fires; the dead callback is not called")


func test_exported_settings_survive_packing_into_a_scene():
	var source := LFViewportLeave.new()
	source.delay = 2.0
	source.max_timeout = 5.0
	source.disabled = false
	var scene := PackedScene.new()
	scene.pack(source)
	source.free()

	var copy: LFViewportLeave = add_child_autofree(scene.instantiate())

	assert_eq(copy.timer.wait_time, 2.0)
	assert_eq(copy.max_timer.wait_time, 5.0)
	assert_false(copy.disabled)
	assert_false(copy.max_timer.paused)
	assert_eq(copy.get_child_count(), 0, "the timers are internal children, never saved")


func test_add_to_parents_the_notifier_and_returns_it_for_chaining():
	var parent: Node2D = add_child_autofree(Node2D.new())
	var notifier := LFViewportLeave.new(_count, 1.0, 0)

	var returned := notifier.add_to(parent)

	assert_same(returned, notifier, "add_to must return the notifier itself")
	assert_same(notifier.get_parent(), parent, "add_to must add the notifier as a child of the given node")


func test_a_chained_add_to_then_set_disabled_tracks_exits():
	var parent: Node2D = add_child_autofree(Node2D.new())

	var notifier := LFViewportLeave.new(_count, 0.02, 0).add_to(parent)
	notifier.set_disabled(false)
	notifier.screen_exited.emit()
	await _wait_for_calls(1)

	assert_eq(calls[0], 1, "a notifier added with add_to must run its timers in the parent's tree")


func test_a_callback_assigned_after_creation_is_called():
	var notifier: LFViewportLeave = add_child_autofree(LFViewportLeave.new())
	notifier.delay = 0.0
	notifier.callback = _count
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_enabling_an_already_enabled_notifier_does_not_report_the_same_departure_again():
	var notifier := _probe(0.02, 0, false)
	notifier.set_disabled(false)
	await _frame_drawn()
	await _wait_for_calls(1)
	assert_eq(calls[0], 1, "precondition: the departure was reported")

	notifier.set_disabled(false)
	await _frame_drawn()

	assert_true(notifier.timer.is_stopped(), "no second delay for the same departure")
	notifier.set_disabled(true)
	notifier.set_disabled(false)
	await _frame_drawn()
	await _wait_for_calls(2)
	assert_eq(calls[0], 2, "disabling, then enabling, checks the node again")


func test_lowering_max_timeout_while_it_counts_reports_once_the_new_limit_is_reached():
	var notifier := _probe(100.0, 300.0, true)
	notifier.set_disabled(false)
	await wait_process_frames(2)

	notifier.max_timeout = 0.05
	await _wait_for_calls(1)

	assert_eq(calls[0], 1, "the new, shorter limit applies to the running fallback")


func test_raising_max_timeout_while_it_counts_keeps_the_time_already_counted():
	var notifier := _probe(100.0, 50.0, true)
	notifier.set_disabled(false)
	await wait_process_frames(3)
	var counted := 50.0 - notifier.max_timer.time_left
	assert_gt(counted, 0.0, "precondition: some time was counted")

	notifier.max_timeout = 80.0

	assert_almost_eq(notifier.max_timer.time_left, 80.0 - counted, 0.0001, "no frame ran in between")
	assert_false(notifier.max_timer.paused)


func test_retiming_a_paused_max_timeout_keeps_it_paused():
	var notifier := _probe(100.0, 50.0, true)

	notifier.max_timeout = 20.0

	assert_true(notifier.max_timer.paused, "only enabled time counts")
	assert_almost_eq(notifier.max_timer.time_left, 20.0, 0.05)


func test_a_fallback_that_already_fired_stays_fired_when_max_timeout_is_raised():
	var notifier := _probe(100.0, 0.02, true)
	notifier.set_disabled(false)
	await _wait_for_calls(1)

	notifier.max_timeout = 0.05
	await _advance_game_time(0.2)

	assert_eq(calls[0], 1, "one departure, one report")
	assert_true(notifier.max_timer.is_stopped())
	assert_eq(notifier.max_timer.wait_time, 0.05, "the new limit is kept for reading")


func test_removing_a_running_fallback_cancels_its_report():
	var notifier := _probe(100.0, 0.05, true)
	notifier.set_disabled(false)

	notifier.max_timeout = 0.0
	await _advance_game_time(0.2)

	assert_eq(calls[0], 0)


func test_a_fallback_set_before_entering_the_tree_counts_once_it_enters():
	var notifier := ProbeLeave.new(_count, 100.0, 0.05)
	notifier.set_disabled(false)
	assert_true(notifier.max_timer.is_stopped(), "a timer outside the tree cannot count")

	add_child_autofree(notifier)
	await _wait_for_calls(1)

	assert_eq(calls[0], 1)


func test_disabling_right_after_a_zero_delay_exit_cancels_the_report():
	var notifier := _probe(0.0, 0, true)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	notifier.set_disabled(true)
	await wait_process_frames(2)

	assert_eq(calls[0], 0, "the deferred report checks the gate again")


func test_freeing_the_notifier_right_after_a_zero_delay_exit_reports_nothing():
	var notifier := ProbeLeave.new(_count, 0.0, 0)
	add_child(notifier)
	notifier.set_disabled(false)

	notifier.screen_exited.emit()
	notifier.free()
	await wait_process_frames(2)

	assert_eq(calls[0], 0)
	assert_engine_error_count(0)


func test_a_notifier_freed_while_its_check_is_pending_reports_nothing():
	var notifier := ProbeLeave.new(_count, 0.0, 0)
	notifier.on_screen = false
	add_child(notifier)
	notifier.set_disabled(false)

	notifier.free()
	await _frame_drawn()

	assert_eq(calls[0], 0)
	assert_engine_error_count(0)


func test_a_notifier_removed_from_the_tree_while_its_check_is_pending_reports_nothing():
	var notifier := _probe(0.0, 0, false)
	notifier.set_disabled(false)

	remove_child(notifier)
	await _frame_drawn()

	assert_eq(calls[0], 0)
	add_child(notifier)


func test_the_unmodified_notifier_judges_visibility_with_is_on_screen():
	# Nothing is drawn headless, so is_on_screen() is false: the node counts as off-screen.
	var notifier: LFViewportLeave = add_child_autofree(LFViewportLeave.new(_count, 0.0, 0))
	assert_false(notifier.is_on_screen(), "precondition: nothing on screen headless")

	notifier.set_disabled(false)
	await _frame_drawn()
	await wait_process_frames(2)

	assert_eq(calls[0], 1)


func test_a_nan_delay_or_max_timeout_is_rejected_and_the_value_is_kept():
	var notifier: LFViewportLeave = autofree(LFViewportLeave.new(Callable(), 2.0, 10.0))
	notifier.delay = NAN
	notifier.max_timeout = NAN
	assert_push_error_count(2)
	assert_eq([notifier.delay, notifier.max_timeout], [2.0, 10.0])
