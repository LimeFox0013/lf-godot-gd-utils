extends GutTest

signal release

var runs: Array = []
var tick: LFCoalescedTick


func before_each():
	runs = []


func _instant(delta: float) -> void:
	runs.append(delta)


func _slow(delta: float) -> void:
	runs.append(delta)
	await release


func test_an_idle_update_runs_at_once_with_the_delta():
	tick = LFCoalescedTick.new(_instant)
	tick.feed(0.5)
	assert_eq(runs, [0.5])
	assert_false(tick.is_running())


func test_frames_fed_while_the_update_runs_are_banked_not_run():
	tick = LFCoalescedTick.new(_slow)
	tick.feed(1.0)
	tick.feed(2.0)
	tick.feed(3.0)
	assert_eq(runs, [1.0])
	assert_true(tick.is_running())
	assert_eq(tick.pending_seconds(), 5.0)


func test_the_next_run_after_the_update_finishes_gets_all_the_banked_time():
	tick = LFCoalescedTick.new(_slow)
	tick.feed(1.0)
	tick.feed(2.0)
	tick.feed(3.0)
	release.emit()
	assert_false(tick.is_running())
	assert_eq(runs, [1.0], 'finishing does not start a run by itself')
	tick.feed(4.0)
	assert_eq(runs, [1.0, 9.0])
	assert_eq(tick.pending_seconds(), 0.0)
	release.emit()


func test_a_synchronous_update_never_banks():
	tick = LFCoalescedTick.new(_instant)
	tick.feed(1.0)
	tick.feed(2.0)
	assert_eq(runs, [1.0, 2.0])
