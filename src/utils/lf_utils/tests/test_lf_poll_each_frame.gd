extends GutTest

class Poller extends RefCounted:
	var steps := 0
	var stop_after := -1

	func step() -> bool:
		steps += 1
		return stop_after < 0 or steps < stop_after


class NodePoller extends Node:
	var steps := 0
	## Shared with the test, so steps stay countable after this node is freed.
	var seen: Array = []

	func step() -> bool:
		steps += 1
		seen.append(steps)
		return true


func test_steps_now_and_then_once_per_frame():
	var poller := Poller.new()
	LFUtils.poll_each_frame(poller, &'step')
	assert_eq(poller.steps, 1, 'the first step runs at once')

	await wait_process_frames(3)

	assert_eq(poller.steps, 4)
	poller.stop_after = 0


func test_stops_when_the_step_returns_false():
	var poller := Poller.new()
	poller.stop_after = 3
	LFUtils.poll_each_frame(poller, &'step')

	await wait_process_frames(6)

	assert_eq(poller.steps, 3)


func test_holds_a_ref_counted_owner_only_weakly():
	var poller := Poller.new()
	var ref: WeakRef = weakref(poller)
	LFUtils.poll_each_frame(poller, &'step')
	poller = null

	assert_null(ref.get_ref(), 'the loop does not keep the owner alive')
	await wait_process_frames(2)


func test_stops_when_a_node_owner_is_freed():
	var node := NodePoller.new()
	var seen := []
	node.seen = seen
	add_child(node)
	LFUtils.poll_each_frame(node, &'step')
	await wait_process_frames(2)
	assert_gt(seen.size(), 1, 'it was polling every frame')
	var before := seen.size()
	node.free()

	await wait_process_frames(3)

	assert_eq(seen.size(), before, 'no step after the owner was freed (an unexpected error would fail too)')


class ValuePoller extends RefCounted:
	var steps := 0
	var result: Variant

	func step() -> Variant:
		steps += 1
		return result


func test_any_return_value_but_true_stops_it_without_an_error():
	for value in [1, 'yes', null, false, [true]]:
		var poller := ValuePoller.new()
		poller.result = value
		LFUtils.poll_each_frame(poller, &'step')
		await wait_process_frames(2)
		assert_eq(poller.steps, 1, 'stopped after a step returning %s' % [value])


func test_a_null_owner_does_nothing():
	LFUtils.poll_each_frame(null, &'step')
	await wait_process_frames(1)
	assert_engine_error_count(0)
