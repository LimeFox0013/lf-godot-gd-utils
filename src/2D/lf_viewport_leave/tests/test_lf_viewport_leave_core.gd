extends GutTest

## The shared timing logic, driven directly rather than through a notifier. A headless run
## draws nothing, so `RenderingServer.frame_post_draw` is emitted by hand where a drawn
## frame is needed.

var owner_node: Node
var core: LFViewportLeaveCore
var fired := 0
var on_screen := true


func before_each() -> void:
	fired = 0
	on_screen = true
	owner_node = Node.new()
	add_child_autofree(owner_node)
	core = LFViewportLeaveCore.new(owner_node, _on_fire, _is_on_screen)


func _on_fire() -> void:
	fired += 1


func _is_on_screen() -> bool:
	return on_screen


func test_the_delay_timer_is_an_internal_child_of_the_owner() -> void:
	assert_eq(core.timer.get_parent(), owner_node)
	assert_eq(owner_node.get_child_count(), 0, "internal children are not counted")


func test_set_delay_sets_the_timer_wait_time_only_when_positive() -> void:
	core.set_delay(2.5)
	assert_eq(core.delay, 2.5)
	assert_eq(core.timer.wait_time, 2.5)

	core.set_delay(0.0)
	assert_eq(core.delay, 0.0)
	assert_eq(core.timer.wait_time, 2.5, "a non-positive delay leaves the wait time alone")


func test_set_max_timeout_creates_then_removes_the_fallback_timer() -> void:
	core.set_max_timeout(3.0)
	assert_not_null(core.max_timer)
	assert_eq(core.max_timer.wait_time, 3.0)
	assert_true(core.max_timer.paused, "paused while the core is disabled")

	core.set_max_timeout(0.0)
	assert_null(core.max_timer)


func test_an_exit_while_enabled_starts_the_delay_and_an_entry_stops_it() -> void:
	core.set_disabled(false)
	core.set_delay(5.0)

	core._on_exited()
	assert_false(core.timer.is_stopped(), "leaving the screen starts the delay")
	core._on_entered()
	assert_true(core.timer.is_stopped(), "coming back cancels it")
	assert_eq(fired, 0)


func test_visibility_changes_are_ignored_while_disabled() -> void:
	core.set_delay(5.0)

	core._on_exited()

	assert_true(core.timer.is_stopped())


func test_an_exit_with_no_delay_reports_on_the_next_idle_frame() -> void:
	core.set_disabled(false)
	core.set_delay(0.0)

	core._on_exited()
	assert_eq(fired, 0, "the report is deferred")
	await wait_process_frames(1)

	assert_eq(fired, 1)


func test_disabling_stops_a_pending_delay() -> void:
	core.set_disabled(false)
	core.set_delay(5.0)
	core._on_exited()

	core.set_disabled(true)

	assert_true(core.timer.is_stopped())


func test_enabling_while_already_off_screen_reports_after_a_drawn_frame() -> void:
	on_screen = false
	core.set_delay(0.0)

	core.set_disabled(false)
	assert_eq(fired, 0, "nothing is judged before a frame is drawn")
	RenderingServer.frame_post_draw.emit()
	await wait_process_frames(2)

	assert_eq(fired, 1, "_schedule_check catches a node that was off-screen all along")


func test_schedule_check_does_nothing_while_disabled() -> void:
	on_screen = false
	core.set_delay(0.0)

	core._schedule_check()
	RenderingServer.frame_post_draw.emit()
	await wait_process_frames(2)

	assert_eq(fired, 0)
