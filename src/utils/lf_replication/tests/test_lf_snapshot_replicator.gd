extends GutTest

## Snapshots here are plain `{entity_id: value}` Dictionaries diffed by the default
## `LFDictionary.diff`; sends are recorded instead of touching a socket.

var checkpoints: Array
var deltas: Array # [{peer, delta}]
var snapshot: Dictionary
var peer_ids: Array
var builds: Array


func before_each():
	checkpoints = []
	deltas = []
	snapshot = {'item-1': Vector3.ZERO}
	peer_ids = [1]
	builds = [0]


func _snapshot() -> Dictionary:
	builds[0] += 1
	return snapshot


func _peers() -> Array:
	return peer_ids


func _send_checkpoint(sent: Variant) -> void:
	checkpoints.append(sent)


func _send_delta(peer: Variant, delta: Variant) -> void:
	deltas.append({'peer': peer, 'delta': delta})


func _replicator(checkpoint_interval := 10.0, delta_interval := 1.0, diff_fn := Callable()) -> LFSnapshotReplicator:
	return LFSnapshotReplicator.new(checkpoint_interval, delta_interval, _snapshot, _peers, diff_fn, _send_checkpoint, _send_delta)


## A replicator whose only checkpoint so far was sent by hand, with its checkpoint clock
## far away so only the delta clock runs.
func _baselined() -> LFSnapshotReplicator:
	var replicator := _replicator(1000.0)
	replicator.checkpoint_now()
	return replicator


func test_no_checkpoint_before_the_interval_elapses():
	_replicator().tick(5.0)

	assert_true(checkpoints.is_empty())


func test_a_checkpoint_is_sent_once_the_interval_elapses():
	_replicator().tick(10.0)

	assert_eq(checkpoints, [snapshot])


func test_checkpoint_time_accumulates_across_smaller_ticks():
	var replicator := _replicator()

	replicator.tick(4.0)
	replicator.tick(4.0)
	assert_true(checkpoints.is_empty(), 'not at the interval yet')
	replicator.tick(4.0)

	assert_eq(checkpoints.size(), 1)


func test_an_overdue_interval_fires_once_not_a_burst():
	var replicator := _replicator()

	replicator.tick(35.0)
	replicator.tick(0.01)
	replicator.tick(0.01)

	assert_eq(checkpoints.size(), 1, 'a long frame sends one checkpoint, not one per frame after it')
	replicator.tick(4.99)
	assert_eq(checkpoints.size(), 2, 'the cadence keeps its phase')


func test_an_overdue_delta_interval_does_not_catch_up_over_the_next_frames():
	var replicator := _baselined()
	builds[0] = 0

	replicator.tick(5.5)
	replicator.tick(0.01)
	replicator.tick(0.01)

	assert_eq(builds[0], 1, 'one delta snapshot for the long frame')


func test_a_second_interval_sends_a_second_checkpoint_built_fresh():
	var replicator := _replicator()
	replicator.tick(10.0)
	snapshot = {'item-1': Vector3.ONE}
	replicator.tick(10.0)

	assert_eq(checkpoints.size(), 2)
	assert_ne(checkpoints[0], checkpoints[1], 'each checkpoint carries the snapshot built for it')


func test_the_signal_carries_the_snapshot_sent():
	var replicator := _replicator()
	var received: Array = []
	replicator.checkpoint_sent.connect(func(sent): received.append(sent))

	replicator.tick(5.0)
	assert_true(received.is_empty())
	replicator.tick(5.0)

	assert_eq(received.size(), 1)
	assert_true(is_same(received[0], checkpoints[0]))


func test_checkpoint_now_restarts_the_checkpoint_clock():
	var replicator := _replicator()
	replicator.tick(9.0)

	replicator.checkpoint_now()
	replicator.tick(9.0)

	assert_eq(checkpoints.size(), 1, 'the next one is a full interval after the manual one')


func test_the_intervals_can_be_read_and_changed():
	var replicator := _replicator(10.0, 1.0)
	assert_eq(replicator.checkpoint_interval, 10.0)
	assert_eq(replicator.delta_interval, 1.0)

	replicator.checkpoint_interval = 2.0
	replicator.delta_interval = 0.0
	assert_eq(replicator.checkpoint_interval, 2.0)
	replicator.tick(2.0)
	assert_eq(checkpoints.size(), 1)


func test_a_checkpoint_gives_every_current_peer_a_baseline():
	peer_ids = [1, 2]
	var replicator := _replicator(1000.0)
	replicator.checkpoint_now()

	assert_true(replicator.has_baseline(1))
	assert_true(replicator.has_baseline(2))
	assert_false(replicator.has_baseline(3))


func test_a_peer_with_no_baseline_yet_receives_nothing():
	var replicator := _replicator(1000.0)

	replicator.tick(1.0)

	assert_true(deltas.is_empty(), 'a joining peer waits for the next checkpoint')
	assert_false(replicator.has_baseline(1))


func test_a_change_since_the_peers_baseline_sends_a_delta():
	var replicator := _baselined()
	snapshot = {'item-1': Vector3(5, 0, 0)}

	replicator.tick(1.0)

	assert_eq(deltas, [{'peer': 1, 'delta': {'changed': {'item-1': Vector3(5, 0, 0)}, 'removed': []}}])


func test_no_change_since_the_baseline_sends_nothing():
	var replicator := _baselined()

	replicator.tick(1.0)

	assert_true(deltas.is_empty())


func test_no_delta_before_its_own_interval_elapses():
	var replicator := _baselined()
	snapshot = {'item-1': Vector3(5, 0, 0)}

	replicator.tick(0.5)

	assert_true(deltas.is_empty())


func test_a_sent_delta_becomes_the_peers_new_baseline():
	var replicator := _baselined()
	snapshot = {'item-1': Vector3(5, 0, 0)}
	replicator.tick(1.0)

	replicator.tick(1.0)

	assert_eq(deltas.size(), 1, 'nothing changed since the delta, so nothing is re-sent')


func test_peers_get_deltas_from_their_own_baselines():
	var replicator := _replicator(1000.0)
	peer_ids = [1, 2]
	replicator.checkpoint_now() # both at x=0
	peer_ids = [2]
	snapshot = {'item-1': Vector3(9, 0, 0)}
	replicator.checkpoint_now() # only peer 2 (say, reconnected) sees x=9
	peer_ids = [1, 2]
	snapshot = {'item-1': Vector3(9, 0, 0), 'item-2': Vector3.ONE}

	replicator.tick(1.0)

	var by_peer := {}
	for entry in deltas:
		by_peer[entry['peer']] = entry['delta']['changed']
	assert_eq(by_peer[1], {'item-1': Vector3(9, 0, 0), 'item-2': Vector3.ONE})
	assert_eq(by_peer[2], {'item-2': Vector3.ONE})


func test_a_shared_baseline_is_diffed_once():
	var replicator := _replicator(1000.0, 1.0, func(new, old):
		builds.append('diff')
		return LFDictionary.diff(old, new))
	peer_ids = [1, 2, 3]
	replicator.checkpoint_now()
	snapshot = {'item-1': Vector3.ONE}

	replicator.tick(1.0)

	assert_eq(deltas.size(), 3)
	assert_eq(builds.count('diff'), 1)


func test_forgetting_a_peer_stops_its_deltas():
	var replicator := _baselined()
	replicator.forget_peer(1)
	snapshot = {'item-1': Vector3(5, 0, 0)}

	replicator.tick(1.0)

	assert_true(deltas.is_empty(), 'its baseline is gone although the peer list still names it')


func test_a_removed_entity_is_reported():
	var replicator := _baselined()
	snapshot = {}

	replicator.tick(1.0)

	assert_eq(deltas[0]['delta']['removed'], ['item-1'])


func test_a_checkpoint_restarts_the_delta_clock():
	var replicator := _replicator(1000.0)
	replicator.tick(0.9)
	replicator.checkpoint_now()
	builds[0] = 0

	replicator.tick(0.2)

	assert_eq(builds[0], 0, 'no snapshot built right after a checkpoint')


func test_a_checkpoint_and_a_delta_due_in_the_same_tick():
	var replicator := _replicator(1.0, 0.5)
	snapshot = {'item-1': Vector3.ONE}

	replicator.tick(1.0)

	assert_eq(checkpoints.size(), 1)
	assert_eq(builds[0], 1, 'the delta clock restarted at the checkpoint, so no delta snapshot was built')
	assert_true(deltas.is_empty())
	replicator.tick(0.49)
	assert_eq(builds[0], 1, 'the next delta is a full interval after the checkpoint')
	replicator.tick(0.01)
	assert_eq(builds[0], 2)


func test_a_cheaper_delta_snapshot_and_a_custom_diff():
	var replicator := _replicator(1000.0, 1.0, func(new, old): return null if new == old else {'x': new})
	var full := {'full': 1}
	var cheap := [1]
	replicator.snapshot_fn = func(): return full
	replicator.delta_snapshot_fn = func(): return cheap[0]
	replicator.checkpoint_now()
	cheap[0] = 2

	replicator.tick(1.0)

	assert_eq(checkpoints, [full])
	assert_eq(deltas, [{'peer': 1, 'delta': {'x': 2}}], 'the delta compares two delta snapshots')


## A full snapshot carries state deltas leave out (`score`); the delta snapshot only the
## units. A client applying every message must keep the score between checkpoints.
func test_state_only_checkpoints_carry_survives_the_deltas_after_a_checkpoint():
	var state := {'units': {'u1': Vector2.ZERO}, 'score': 5}
	var replicator := _replicator(1000.0, 1.0)
	replicator.snapshot_fn = func(): return {'units': state['units'], 'score': state['score']}
	replicator.delta_snapshot_fn = func(): return {'units': state['units']}
	var client := {}
	replicator.send_checkpoint = func(sent: Dictionary) -> void: client.assign(sent.duplicate(true))
	replicator.send_delta = func(_peer: Variant, diff: Dictionary) -> void:
		deltas.append(diff)
		client.assign(LFDictionary.apply_diff(client, diff))
	replicator.checkpoint_now()

	state['units'] = {'u1': Vector2.ONE, 'u2': Vector2.ONE}
	replicator.tick(1.0)
	state['units'] = {'u2': Vector2.ONE}
	replicator.tick(1.0)
	replicator.checkpoint_now()
	state['units'] = {'u2': Vector2.ZERO}
	replicator.tick(1.0)

	assert_eq(deltas.size(), 3)
	for diff in deltas:
		assert_false(diff[LFDictionary.KEY_REMOVED].has('score'), 'a key only checkpoints carry is never reported removed')
	assert_eq(client, {'units': {'u2': Vector2.ZERO}, 'score': 5}, 'the client stays in sync across a checkpoint')


func test_a_checkpoint_builds_one_delta_snapshot_as_the_baseline():
	var delta_builds := [0]
	var replicator := _replicator(1000.0, 1.0)
	replicator.delta_snapshot_fn = func():
		delta_builds[0] += 1
		return {}
	replicator.checkpoint_now()

	assert_eq(delta_builds[0], 1)


func test_a_null_diff_sends_nothing():
	var replicator := _replicator(1000.0, 1.0, func(_new, _old): return null)
	replicator.checkpoint_now()
	snapshot = {'item-1': Vector3.ONE}

	replicator.tick(1.0)

	assert_true(deltas.is_empty())


func test_the_callables_can_be_swapped_after_construction():
	var replicator := _replicator(10.0, 1.0)
	var other_checkpoints := []
	var other_deltas := []
	replicator.peer_ids_fn = func(): return [7]
	replicator.snapshot_fn = func(): return {'x': 1}
	replicator.send_checkpoint = func(snapshot): other_checkpoints.append(snapshot)
	replicator.send_delta = func(peer_id, diff): other_deltas.append([peer_id, diff])
	replicator.diff_fn = func(_new, _old): return 'changed'

	replicator.checkpoint_now()
	replicator.tick(1.0)

	assert_eq(other_checkpoints, [{'x': 1}])
	assert_eq(other_deltas, [[7, 'changed']])
	assert_true(checkpoints.is_empty() and deltas.is_empty(), 'the original callables are no longer used')


func test_a_peer_dropped_while_its_delta_is_sent_stays_forgotten_and_the_others_still_get_theirs():
	var replicator := _replicator(1000.0)
	peer_ids = [1, 2]
	replicator.checkpoint_now()
	snapshot = {'item-1': Vector3.ONE}
	# A send that fails and disconnects the peer on the spot.
	replicator.send_delta = func(peer: Variant, delta: Variant) -> void:
		deltas.append({'peer': peer, 'delta': delta})
		if peer == 1:
			peer_ids.erase(1)
			replicator.forget_peer(1)

	replicator.tick(1.0)

	replicator.send_delta = Callable() # the lambda holds the replicator: break the cycle

	assert_false(replicator.has_baseline(1), 'the forgotten peer does not get its baseline back')
	assert_eq(deltas.map(func(entry): return entry['peer']), [1, 2], 'removing a peer mid-send skips no one')


func test_a_peer_dropped_while_a_checkpoint_is_sent_stays_forgotten():
	var replicator := _replicator(1000.0)
	peer_ids = [1, 2]
	replicator.send_checkpoint = func(sent: Variant) -> void:
		checkpoints.append(sent)
		replicator.forget_peer(1)

	replicator.checkpoint_now()
	replicator.send_checkpoint = Callable() # the lambda holds the replicator: break the cycle

	assert_false(replicator.has_baseline(1))
	assert_true(replicator.has_baseline(2))


func test_the_peer_list_may_be_a_packed_int_array():
	var replicator := LFSnapshotReplicator.new(1000.0, 1.0, _snapshot, func() -> PackedInt32Array: return PackedInt32Array([1, 2]), Callable(), _send_checkpoint, _send_delta)
	replicator.checkpoint_now()

	assert_true(replicator.has_baseline(1) and replicator.has_baseline(2), 'what multiplayer.get_peers() returns works as is')


func test_a_zero_checkpoint_interval_sends_one_every_tick_and_no_deltas():
	var replicator := _replicator(0.0, 0.0)
	for i in 3:
		snapshot = {'item-1': Vector3(i, 0, 0)}
		replicator.tick(0.016)
	assert_eq(checkpoints.size(), 3)
	assert_true(deltas.is_empty(), 'a checkpoint every tick leaves no tick for a delta')


func test_a_zero_delta_interval_diffs_every_tick():
	var replicator := _baselined()
	replicator.delta_interval = 0.0
	for i in 3:
		snapshot = {'item-1': Vector3(i + 1, 0, 0)}
		replicator.tick(0.016)
	assert_eq(deltas.size(), 3)
	assert_eq(deltas[2]['delta']['changed'], {'item-1': Vector3(3, 0, 0)}, 'each against the previous delta')


func test_an_empty_changed_removed_diff_sends_nothing_and_keeps_the_baseline():
	var empty := {LFDictionary.KEY_CHANGED: {}, LFDictionary.KEY_REMOVED: []}
	var replicator := _replicator(1000.0, 1.0, func(_new, _old): return empty)
	replicator.checkpoint_now()
	var baseline: Variant = replicator._baselines[1]
	snapshot = {'item-1': Vector3.ONE}

	replicator.tick(1.0)

	assert_true(deltas.is_empty())
	assert_same(replicator._baselines[1], baseline, 'the baseline stays')


func test_a_custom_diff_of_another_shape_is_always_sent():
	var replicator := _replicator(1000.0, 1.0, func(_new, _old): return {LFDictionary.KEY_CHANGED: {}})
	replicator.checkpoint_now()

	replicator.tick(1.0)

	assert_eq(deltas.size(), 1, 'only null or an empty {changed, removed} pair means no change')


func test_forgetting_an_unknown_peer_is_a_no_op():
	var replicator := _baselined()
	replicator.forget_peer(42)
	assert_true(replicator.has_baseline(1))
