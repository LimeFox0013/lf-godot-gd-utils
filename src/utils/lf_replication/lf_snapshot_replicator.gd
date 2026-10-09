## Sends state from a server to its peers: a full copy now and then, and only what
## changed in between.
##
## It runs on two clocks: a full "checkpoint" to everyone every `checkpoint_interval`
## seconds, and between checkpoints a per-peer "delta" (just the changes) every
## `delta_interval` seconds. It is ticked explicitly (`tick(delta)`), so it is deterministic
## and testable without waiting on real time. It sends nothing itself: you give it the
## functions that build the state and send messages.
##
## Each peer (a connected client) has a baseline: what it last saw. A peer starts with none
## and gets no delta until the next checkpoint (a joining peer waits for one). A checkpoint
## resets every current peer's baseline and restarts the delta clock; a sent delta
## advances that peer's baseline to the snapshot it was diffed from. A delta is computed
## once per distinct baseline (peers usually share one) and nothing is sent to a peer whose
## state has not changed. `forget_peer()` drops a disconnected peer's baseline (a peer the list no longer returns keeps it until then); it may be
## called from inside a send (a failed send that disconnects the peer).
##
## The baseline advances when a delta is handed to `send_delta`, not when the peer
## receives it, so the transport must deliver every delta, in order (a WebSocket or a
## reliable ordered RPC). A lost or reordered delta leaves that peer wrong until the next
## checkpoint, which replaces its whole state.
##
## The snapshot type is up to the caller: `snapshot_fn` builds the full state, the optional
## `delta_snapshot_fn` a cheaper one for deltas, and `diff_fn(new, old)` compares two
## snapshots of the kind deltas use, returning null, or a `{changed, removed}` Dictionary
## with both empty, for "no change". Without a `diff_fn`, snapshots must be Dictionaries
## and `LFDictionary.diff` is used. With a `delta_snapshot_fn`, a checkpoint also builds
## one delta snapshot and makes it the baseline, so deltas always compare two delta
## snapshots: state only the full snapshot holds is never reported changed or removed by a
## delta; it reaches peers with each checkpoint.
class_name LFSnapshotReplicator
extends RefCounted

## Emitted right after a checkpoint is sent, with the snapshot sent.
signal checkpoint_sent(snapshot: Variant)

## Seconds between checkpoints; 0 or less sends one every tick.
var checkpoint_interval: float:
	get:
		return _checkpoint_timer.interval
	set(value):
		_checkpoint_timer.interval = value
## Seconds between deltas; 0 or less diffs every tick.
var delta_interval: float:
	get:
		return _delta_timer.interval
	set(value):
		_delta_timer.interval = value
## `() -> Variant`: the full state now, built fresh on each call.
var snapshot_fn: Callable
## `() -> Variant`: the state deltas are diffed from; empty uses `snapshot_fn`. It must
## hold, for whatever part of the state it covers, the same values the full snapshot holds
## at that moment: a checkpoint builds one as every peer's baseline, so a value that
## differs from the checkpoint's would never reach a peer that applies only deltas to it.
## State it leaves out travels only with checkpoints.
var delta_snapshot_fn: Callable
## `() -> Array`: the ids of the peers to replicate to, read fresh each time (a
## `PackedInt32Array`, such as `multiplayer.get_peers()`, works too).
var peer_ids_fn: Callable
## `(new, old) -> Variant`: what changed, or null / an empty `{changed, removed}` for
## nothing; empty uses `LFDictionary.diff(old, new)`.
var diff_fn: Callable
## `(snapshot) -> void`: sends a checkpoint to every peer.
var send_checkpoint: Callable
## `(peer_id, diff) -> void`: sends one peer its delta.
var send_delta: Callable

## peer id -> the snapshot it last saw.
var _baselines: Dictionary = {}
var _checkpoint_timer := LFIntervalTimer.new(0.0)
var _delta_timer := LFIntervalTimer.new(0.0)


## Creates a replicator. Each argument sets the property of the matching role (see each
## property's doc): `checkpoint_seconds` and `delta_seconds` set the two intervals,
## `build_snapshot` is `snapshot_fn`, `list_peer_ids` is `peer_ids_fn`, `compute_diff` is
## `diff_fn` (pass `Callable()` to use `LFDictionary.diff`), `checkpoint_sender` is
## `send_checkpoint` and `delta_sender` is `send_delta`. Nothing is sent until `tick()` or
## `checkpoint_now()`.
func _init(checkpoint_seconds: float, delta_seconds: float, build_snapshot: Callable, list_peer_ids: Callable, compute_diff: Callable, checkpoint_sender: Callable, delta_sender: Callable) -> void:
	checkpoint_interval = checkpoint_seconds
	delta_interval = delta_seconds
	snapshot_fn = build_snapshot
	peer_ids_fn = list_peer_ids
	diff_fn = compute_diff
	send_checkpoint = checkpoint_sender
	send_delta = delta_sender


## Call once per frame. A due checkpoint is sent, otherwise a due delta. A long frame that
## spans several intervals sends one, not one per frame afterwards. A checkpoint restarts
## the delta clock, so the next delta is a full `delta_interval` after it.
func tick(delta: float) -> void:
	if _fires(_checkpoint_timer, delta):
		_checkpoint()
	elif _fires(_delta_timer, delta):
		_send_deltas()


## Sends a checkpoint now and restarts both clocks — for a moment that must not wait,
## such as a newly joined peer.
func checkpoint_now() -> void:
	_checkpoint_timer.restart()
	_checkpoint()


## Forgets `peer_id`'s baseline; it gets nothing more until the next checkpoint.
func forget_peer(peer_id: Variant) -> void:
	_baselines.erase(peer_id)


## Returns `true` when `peer_id` has seen a checkpoint (and so receives deltas).
func has_baseline(peer_id: Variant) -> bool:
	return _baselines.has(peer_id)


func _checkpoint() -> void:
	var snapshot: Variant = snapshot_fn.call()
	# Deltas compare delta snapshots only, so the baseline is one built at the same moment.
	var baseline: Variant = snapshot if delta_snapshot_fn.is_null() else delta_snapshot_fn.call()
	# Baselines are set before sending, so a peer forgotten during the send stays forgotten.
	for peer_id: Variant in _peer_ids():
		_baselines[peer_id] = baseline
	send_checkpoint.call(snapshot)
	_delta_timer.restart()
	checkpoint_sent.emit(snapshot)


func _send_deltas() -> void:
	var snapshot: Variant = (snapshot_fn if delta_snapshot_fn.is_null() else delta_snapshot_fn).call()
	# [baseline, diff] pairs, matched by identity: peers that saw one checkpoint share it.
	var computed: Array = []
	for peer_id: Variant in _peer_ids():
		if not _baselines.has(peer_id):
			continue
		var baseline: Variant = _baselines[peer_id]
		var diff: Variant = null
		var found := false
		for pair: Variant in computed:
			if is_same(pair[0], baseline):
				diff = pair[1]
				found = true
				break
		if not found:
			diff = _diff(snapshot, baseline)
			computed.append([baseline, diff])
		if _is_empty(diff):
			continue
		_baselines[peer_id] = snapshot
		send_delta.call(peer_id, diff)


## A copy of the peer list, so a send that removes a peer from it skips no one.
func _peer_ids() -> Array:
	return Array(peer_ids_fn.call()).duplicate()


## Whether `timer` fires this tick; whole intervals banked beyond it are dropped so a long
## frame does not turn into a burst on the frames after it.
static func _fires(timer: LFIntervalTimer, delta: float) -> bool:
	if not timer.tick(delta):
		return false
	timer.drain()
	return true


func _diff(new: Variant, old: Variant) -> Variant:
	if not diff_fn.is_null():
		return diff_fn.call(new, old)
	return LFDictionary.diff(old, new)


static func _is_empty(diff: Variant) -> bool:
	if diff == null:
		return true
	if diff is Dictionary and diff.has(LFDictionary.KEY_CHANGED) and diff.has(LFDictionary.KEY_REMOVED):
		return diff[LFDictionary.KEY_CHANGED].is_empty() and diff[LFDictionary.KEY_REMOVED].is_empty()
	return false
