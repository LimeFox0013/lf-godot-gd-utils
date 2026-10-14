extends GutTest

const IDLE := 120.0
const AFTER_FINISH := 30.0
const CHECK := 2.0
const NO_SUCH_PID := 999999

var lifetime: LFServerLifetime


func before_each():
	lifetime = LFServerLifetime.new(IDLE, AFTER_FINISH, CHECK)


func _until_parent_answered() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while lifetime.parent_watch.is_checking() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		lifetime.tick(0.0, 1)
	assert_false(lifetime.parent_watch.is_checking(), 'the parent check answered')


func test_it_goes_idle_when_nobody_is_connected_for_long_enough():
	assert_eq(lifetime.tick(IDLE - 1.0, 0), LFServerLifetime.Reason.NONE)
	assert_eq(lifetime.tick(1.0, 0), LFServerLifetime.Reason.IDLE)


func test_a_connected_client_resets_the_idle_clock():
	lifetime.tick(IDLE - 1.0, 0)
	lifetime.tick(1.0, 1)
	assert_eq(lifetime.tick(IDLE - 1.0, 0), LFServerLifetime.Reason.NONE)


func test_it_finishes_a_while_after_finish_is_called():
	lifetime.finish()
	assert_eq(lifetime.tick(AFTER_FINISH - 1.0, 1), LFServerLifetime.Reason.NONE)
	assert_eq(lifetime.tick(1.0, 1), LFServerLifetime.Reason.FINISHED)


func test_it_does_not_finish_before_finish_is_called():
	assert_eq(lifetime.tick(AFTER_FINISH * 2.0, 1), LFServerLifetime.Reason.NONE)


func test_finished_is_reported_before_idle():
	lifetime.finish()
	assert_eq(lifetime.tick(IDLE * 2.0, 0), LFServerLifetime.Reason.FINISHED)


func test_finish_called_again_restarts_the_countdown():
	lifetime.finish()
	lifetime.tick(AFTER_FINISH - 1.0, 1)
	lifetime.finish()
	assert_eq(lifetime.tick(AFTER_FINISH - 1.0, 1), LFServerLifetime.Reason.NONE)


func test_nothing_is_watched_without_a_parent_pid():
	lifetime.tick(CHECK * 2.0, 1)
	assert_null(lifetime.parent_watch)


func test_a_live_parent_keeps_it_running():
	lifetime.parent_pid = OS.get_process_id()
	lifetime.tick(CHECK + 0.1, 1)
	await _until_parent_answered()
	assert_eq(lifetime.tick(CHECK, 1), LFServerLifetime.Reason.NONE)


func test_a_gone_parent_is_reported_after_its_check_interval():
	lifetime.parent_pid = NO_SUCH_PID
	assert_eq(lifetime.tick(CHECK * 0.5, 1), LFServerLifetime.Reason.NONE, 'no check before the interval')
	lifetime.tick(CHECK * 0.6, 1)
	await _until_parent_answered()
	assert_eq(lifetime.tick(0.0, 1), LFServerLifetime.Reason.PARENT_GONE)
