extends GutTest

var receiver: LFSnapshotReceiver


func before_each():
	receiver = LFSnapshotReceiver.new(func(snapshot, delta): return snapshot + delta)


func test_starts_with_no_state():
	assert_null(receiver.current)


func test_a_delta_before_any_checkpoint_is_ignored():
	assert_false(receiver.on_delta(5))
	assert_null(receiver.current)


func test_a_checkpoint_replaces_the_state_and_a_delta_changes_it():
	receiver.on_checkpoint(10)
	assert_true(receiver.on_delta(5))
	assert_eq(receiver.current, 15)
	receiver.on_checkpoint(1)
	assert_eq(receiver.current, 1)


func test_a_receiver_without_a_valid_apply_function_ignores_deltas():
	var bare := LFSnapshotReceiver.new()
	bare.on_checkpoint(1)
	assert_false(bare.on_delta(2))
	assert_eq(bare.current, 1)
