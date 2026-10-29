# lf_replication

> Keeps a game on a server and the players' screens in sync: the server sends what changed, and each player's game plays those updates back smoothly.

| | |
|---|---|
| **Files** | `lf_snapshot_replicator.gd`, `lf_snapshot_receiver.gd`, `lf_interpolation_buffer.gd`, `lf_playback_clock.gd` |
| **Tests** | `tests/test_lf_snapshot_replicator.gd`, `tests/test_lf_snapshot_receiver.gd`, `tests/test_lf_interpolation.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFIntervalTimer`, `LFDictionary`, `LFLogger` (`LFInterpolationBuffer` reports a sample that is not finite) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFInterpolationBuffer` | Object: create it with `.new()` |
| `LFPlaybackClock` | Object: create it with `.new()` |
| `LFSnapshotReceiver` | Object: create it with `.new()` |
| `LFSnapshotReplicator` | Object: create it with `.new()` |

## When to use it

Use it when a server runs the game and players' clients only show it: unit positions,
health, scores. On the server, `LFSnapshotReplicator` decides what to send and when: a full
copy every second, and in between only what changed (a unit that stood still is left
out of those updates). On each client, `LFPlaybackClock` and one `LFInterpolationBuffer` per value play
those updates back smoothly, a tenth of a second in the past, so a unit glides instead of
teleporting 10 times a second. Godot's `MultiplayerSynchronizer` does a similar job for
scene nodes over Godot's own multiplayer; use these classes when you need control over
the format, bandwidth or transport (for example over `LFSocket`), or plain data instead
of nodes.

## Step by step

**Before you start:** the classes do not send anything over the network themselves. You
give them functions that do (an RPC, a WebSocket, ...). To see the whole idea without a
network, this demo runs the "server" and the "client" in **one scene** and passes the
updates between them with a plain function call. A sprite shows the raw updates (it
jumps), and a second one shows the smoothed result (it glides). Use any picture, for
example the `icon.svg` every new project has.

1. In the Godot editor choose *Scene → New Scene*, then click **Other Node**, pick
   **Node2D**, and press *Create*. Save it (*Ctrl+S*, Cmd+S on macOS) as `replication_demo.tscn`.
2. Add two children: right-click the Node2D and choose *Add Child Node* (or press the **+**
   button in the Scene dock), search `Sprite2D`, press *Create*, and do it twice. Rename
   them `Raw` and `Smooth` (select one and press *F2*). Select each, find **Texture** in the
   Inspector (the panel on the right), and drag `icon.svg` from the FileSystem dock onto it.
3. Right-click the root Node2D, choose *Attach Script* and press *Create*.
4. Replace everything in the script with this:

```gdscript
extends Node2D

@onready var raw: Sprite2D = $Raw
@onready var smooth: Sprite2D = $Smooth

# ---- The "server" half ----
var unit_position := Vector2.ZERO      # the real position of our one unit
var server_time := 0.0                 # the server's clock, in seconds
var replicator: LFSnapshotReplicator

# ---- The "client" half ----
var clock := LFPlaybackClock.new(0.3)         # show the world 0.3 seconds in the past
var buffer := LFInterpolationBuffer.new()     # remembers the stamped positions


func _ready() -> void:
	# A full copy every 1 second; only the changes every 0.2 seconds.
	# The last two arguments are the functions that "send" (here: call the client).
	# Callable() means "use the default way to compare"; a Callable is a function passed as a value.
	replicator = LFSnapshotReplicator.new(1.0, 0.2, _snapshot, _peer_ids, Callable(),
			_send_full, _send_changes)
	replicator.checkpoint_now()   # the first full copy


func _process(delta: float) -> void:   # delta = seconds since the last frame
	# Server: move the unit in a circle and let the replicator decide what to send.
	server_time += delta
	unit_position = Vector2(300, 200) + Vector2(150, 100) * Vector2(cos(server_time), sin(server_time))
	replicator.tick(delta)

	# Client: move playback time on, then read the smoothed position at that time.
	var playback_time := clock.advance(delta)
	var shown: Variant = buffer.sample_at(playback_time)
	if shown != null:
		smooth.position = shown


# What the server shares: a fresh Dictionary each call (unit id -> position).
func _snapshot() -> Dictionary:
	return {"unit-1": unit_position}


# Who receives it. One pretend player, with id 1.
func _peer_ids() -> Array:
	return [1]


func _send_full(snapshot: Dictionary) -> void:
	_receive(server_time, snapshot)


func _send_changes(_peer_id: int, diff: Dictionary) -> void:
	# diff["removed"] lists the ids that are gone; this demo's one unit never goes
	# (Usage below shows a client that handles it).
	_receive(server_time, diff["changed"])


# Client: called with every update from the server.
func _receive(stamp_time: float, positions: Dictionary) -> void:
	for id in positions:
		raw.position = positions[id]   # the raw update: jumps
		# Pass clock.latest BEFORE stamp(): it tells the buffer when the previous update was.
		buffer.add_sample(stamp_time, positions[id], clock.latest)
	clock.stamp(stamp_time)
```

5. Press *F6* (Run Current Scene). You should see two icons moving around an oval: `Raw`
   jumps five times a second (once per 0.2-second update), while `Smooth` follows the same
   path gliding, a little behind. The first fraction of a second, `Smooth` waits for data.
6. Make it yours: change `0.2` (how often changes are sent, in seconds) and `0.3` (how far
   in the past the client plays, in seconds; use about two update intervals so one late
   update does not cause a stutter). In your game, replace `_send_full` and `_send_changes`
   with real network sends, and `_receive` runs on the player's machine.

## API

Everything the class offers; you only need the rows used above to get started.

### LFSnapshotReplicator (server)

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFSnapshotReplicator.new(checkpoint_seconds: float, delta_seconds: float, build_snapshot: Callable, list_peer_ids: Callable, compute_diff: Callable, checkpoint_sender: Callable, delta_sender: Callable)` | Sets, in order, `checkpoint_interval`, `delta_interval`, `snapshot_fn`, `peer_ids_fn`, `diff_fn` (`Callable()`: `LFDictionary.diff`), `send_checkpoint`, `send_delta`. Sends nothing until `tick()` or `checkpoint_now()`. |
| `checkpoint_sent` | `signal checkpoint_sent(snapshot: Variant)` | After each checkpoint is sent. |
| `checkpoint_interval` | `var checkpoint_interval: float` | Seconds between full checkpoints; 0 or less sends one every tick. |
| `delta_interval` | `var delta_interval: float` | Seconds between deltas; 0 or less diffs every tick. |
| `snapshot_fn` | `var snapshot_fn: Callable` | `() -> Variant`: the full state now, built fresh each call. |
| `delta_snapshot_fn` | `var delta_snapshot_fn: Callable` | Optional `() -> Variant`: a cheaper state for deltas; empty uses `snapshot_fn`. A checkpoint also builds one and makes it the peers' baseline, so deltas compare delta snapshots only. It must hold the same values the full snapshot holds for the part it covers; what it leaves out travels only with checkpoints. |
| `peer_ids_fn` | `var peer_ids_fn: Callable` | `() -> Array` (or `PackedInt32Array`, such as `multiplayer.get_peers()`): the peers to replicate to, read fresh each time. |
| `diff_fn` | `var diff_fn: Callable` | `(new, old) -> Variant`: what changed between two snapshots of the kind deltas use (`delta_snapshot_fn`'s when set); null or an empty `{changed, removed}` means nothing. Empty uses `LFDictionary.diff(old, new)`. |
| `send_checkpoint` | `var send_checkpoint: Callable` | `(snapshot) -> void`: sends a checkpoint to every peer. |
| `send_delta` | `var send_delta: Callable` | `(peer_id, diff) -> void`: sends one peer its delta. |
| `tick` | `tick(delta: float) -> void` | Once per frame: a due checkpoint, otherwise due deltas. A frame spanning several intervals sends once, with no catch-up on later frames. |
| `checkpoint_now` | `checkpoint_now() -> void` | Sends a checkpoint now and restarts both clocks. |
| `forget_peer` | `forget_peer(peer_id: Variant) -> void` | Drops a peer's baseline (call on disconnect). |
| `has_baseline` | `has_baseline(peer_id: Variant) -> bool` | Whether the peer has seen a checkpoint. |

### LFSnapshotReceiver (client)

| Member | Signature | Description |
|---|---|---|
| `new` | `LFSnapshotReceiver.new(delta_applier: Callable = Callable())` | Sets `apply_delta_fn`: `(snapshot, delta) -> Variant`, returns the snapshot with the delta applied. With no valid function every delta is ignored. |
| `on_checkpoint` | `on_checkpoint(snapshot: Variant) -> void` | Replaces the state. |
| `on_delta` | `on_delta(delta: Variant) -> bool` | Applies a delta; false and no change before the first checkpoint or without a valid `apply_delta_fn`. |
| `apply_delta_fn` | `var apply_delta_fn: Callable` | The function `on_delta` calls. |
| `current` | `var current: Variant` | The newest state, null before the first checkpoint. |

### LFInterpolationBuffer (client, one per value)

| Member | Signature | Description |
|---|---|---|
| `add_sample` | `add_sample(time: float, value: Variant, previous_time: float = -INF) -> void` | Records a stamped value. `previous_time` (the previous update's stamp) fills in "it stood still until then". Older or equal stamps are ignored. A `time` or `value` that is not finite (inf or NaN in a float, Vector2/3/4, Color, Quaternion, Basis or Transform2D/3D) is not recorded and pushes a warning through `LFLogger`, so the last good value keeps playing. |
| `is_finite_value` | `static is_finite_value(value: Variant) -> bool` | `false` for a float, vector, Color, Quaternion, Basis or Transform with an inf or NaN component; `true` otherwise, for every other type too. |
| `sample_at` | `sample_at(time: float) -> Variant` | The value at `time`, blended between the samples around it (see Notes for which types blend); the first sample before it, the last after. Drops samples played past. Null when empty. |
| `is_empty` | `is_empty() -> bool` | Whether no sample is held. |
| `size` | `size() -> int` | How many samples are held. |
| `latest_time` | `latest_time() -> float` | The newest sample's stamp; -INF when empty. |
| `clear` | `clear() -> void` | Drops every sample. |

### LFPlaybackClock (client, one per stream)

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFPlaybackClock.new(trail_seconds := DEFAULT_DELAY, drift_correction_rate := DEFAULT_CORRECTION_RATE, jump_after_seconds := DEFAULT_SNAP_SECONDS)` (0.1, 0.5, 0.5) | Sets `delay`, `correction_rate` and `snap_seconds`. |
| `DEFAULT_DELAY` | `const DEFAULT_DELAY: float` | `0.1`, the default `delay` in seconds. |
| `DEFAULT_CORRECTION_RATE` | `const DEFAULT_CORRECTION_RATE: float` | `0.5`, the default `correction_rate` (share of the gap per second). |
| `DEFAULT_SNAP_SECONDS` | `const DEFAULT_SNAP_SECONDS: float` | `0.5`, the default `snap_seconds`. |
| `delay` | `var delay: float` | Seconds playback trails the newest stamp. |
| `correction_rate` | `var correction_rate: float` | Share of a small drift closed per second. |
| `snap_seconds` | `var snap_seconds: float` | A drift larger than this jumps instead. |
| `time` | `var time: float` | Playback time; -INF before the first stamp. May be set. |
| `latest` | `var latest: float` | Newest stamp heard; -INF before the first. |
| `stamp` | `stamp(stamp_time: float) -> void` | Notes an update's server time; the first starts playback `delay` behind it. Older, equal and non-finite stamps are ignored. |
| `advance` | `advance(delta: float) -> float` | Moves playback on (real speed, nudged toward `latest - delay`, never past `latest`); returns it. |
| `is_started` | `is_started() -> bool` | Whether a stamp has been heard. |
| `reset` | `reset() -> void` | Forgets every stamp; playback waits for the next. |

## Usage

Two scripts. The server one owns the state; the client one shows it, adding a sprite for
each unit it hears of and removing it once the unit is gone. A third script runs both in
one scene and stands in for the network, so the example runs as is: save the three
scripts at the top of the project (`res://`, beside the `icon.svg` every new project has,
which the client draws), attach `replication_demo.gd` to the root Node2D of a new scene
and press *F6*. Unit `a` circles; unit `b` disappears after 3 seconds.
In your game, replace the two `client.receive_...` lines with your network send (an RPC,
`LFSocketServer`, ...).

```gdscript
# replication_server.gd: on the server, a Node that owns the game state.
extends Node

var unit_positions := {}          # unit id -> Vector2, moved by your game code
var connected_peers: Array = []   # ids of the connected players
var client: Node                  # stands in for the network in this example
var server_time := 0.0
var replicator: LFSnapshotReplicator


func _ready() -> void:
	# A full copy every 1 s; only the changes every 0.1 s.
	replicator = LFSnapshotReplicator.new(1.0, 0.1, _snapshot, _peer_ids, Callable(),
			_send_full, _send_changes)


func _process(delta: float) -> void:
	server_time += delta
	replicator.tick(delta)


func on_peer_joined(peer_id: int) -> void:
	connected_peers.append(peer_id)
	replicator.checkpoint_now()   # the newcomer gets a full copy right away


func on_peer_left(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	replicator.forget_peer(peer_id)


func _snapshot() -> Dictionary:
	return unit_positions.duplicate()   # a fresh copy each call, never the same object


func _peer_ids() -> Array:
	return connected_peers


func _send_full(snapshot: Dictionary) -> void:
	client.receive_full(server_time, snapshot)   # in your game: send to every peer


func _send_changes(_peer_id: int, diff: Dictionary) -> void:
	# in your game: send to this one peer
	client.receive_changes(server_time, diff["changed"], diff["removed"])
```

```gdscript
# replication_client.gd: on each player's game, a Node2D that shows the units.
extends Node2D

var clock := LFPlaybackClock.new(0.2)   # show the world 0.2 s in the past
var buffers := {}                       # unit id -> LFInterpolationBuffer
var sprites := {}                       # unit id -> the Sprite2D that shows it


# Call with every checkpoint. It holds every unit, so one missing from it is gone.
func receive_full(server_time: float, positions: Dictionary) -> void:
	var gone := []
	for id in buffers:
		if not positions.has(id):
			gone.append(id)
	receive_changes(server_time, positions, gone)


# Call with every delta: the units that changed, and the ids of the units that are gone.
func receive_changes(server_time: float, changed: Dictionary, removed: Array) -> void:
	for id in removed:
		if sprites.has(id):
			sprites[id].queue_free()
		sprites.erase(id)
		buffers.erase(id)
	for id in changed:
		if not buffers.has(id):   # a unit seen for the first time
			buffers[id] = LFInterpolationBuffer.new()
			var sprite := Sprite2D.new()
			sprite.texture = preload("res://icon.svg")
			add_child(sprite)
			sprites[id] = sprite
		# Pass clock.latest BEFORE stamp(): it says when the previous update was.
		buffers[id].add_sample(server_time, changed[id], clock.latest)
	clock.stamp(server_time)


func _process(delta: float) -> void:
	var playback_time := clock.advance(delta)
	for id in buffers:
		var shown: Variant = buffers[id].sample_at(playback_time)
		if shown != null:
			sprites[id].position = shown
```

```gdscript
# replication_demo.gd: the root Node2D of a test scene. It runs the server and one client
# in one scene and plays the network's part with plain function calls.
extends Node2D

var server: Node = preload("res://replication_server.gd").new()
var client: Node2D = preload("res://replication_client.gd").new()
var time := 0.0


func _ready() -> void:
	server.client = client
	add_child(server)
	add_child(client)
	server.unit_positions = {"a": Vector2(100, 100), "b": Vector2(100, 300)}
	server.on_peer_joined(1)


func _process(delta: float) -> void:
	time += delta
	server.unit_positions["a"] = Vector2(300, 200) + Vector2(150, 100) * Vector2(cos(time), sin(time))
	if time > 3.0:
		server.unit_positions.erase("b")   # unit b is destroyed after 3 seconds
```

## Notes

- A "peer" is one connected player. A "baseline" is what that player last saw, which the next delta is measured against. A joining peer gets no delta until the next checkpoint; call `checkpoint_now()` if it should not wait.
- A checkpoint resets the baselines of the peers `peer_ids_fn` returns *at that moment* and restarts the delta clock: no delta is computed in the tick that sends a checkpoint, and the next one is a full `delta_interval` later.
- Build each snapshot fresh on every call; never change an old one in place. The replicator compares by object identity so that players who saw the same checkpoint share one comparison, and an edited old snapshot would hide changes.
- `send_checkpoint` and `send_delta` may call `forget_peer()` or change the peer list (a failed send that disconnects the peer): the peer stays forgotten and the other peers still get their sends.
- **Delivery.** A peer's baseline moves on when its delta is handed to `send_delta`, not when the peer gets it, so the transport must deliver every delta, in order (a WebSocket or a reliable ordered RPC). A lost or reordered delta leaves that peer wrong until the next checkpoint; the client should replace its whole state with each checkpoint (as `receive_full` above does) so that the error ends there.
- **A cheaper delta snapshot.** With `delta_snapshot_fn` set, every checkpoint builds one extra delta snapshot as the baseline, and deltas compare delta snapshots only. State the full snapshot holds and the delta snapshot leaves out (scores, settings) is never reported changed or removed by a delta and reaches peers with each checkpoint.
- "No change" is a null diff or a `{changed, removed}` Dictionary with both empty; nothing is sent then and the baseline stays.
- Client side: pass `clock.latest` as `previous_time` *before* calling `clock.stamp()` for the same update, so a value an update left out is known to have stood still.
- `sample_at` assumes playback only moves forward (it forgets samples it has played past); to rewind, `clear()` and refill. Samples are only dropped by `sample_at`, so a buffer that is fed but never sampled grows without limit.
- Blending (smoothly mixing two values) covers float, Vector2/3/4, Color, Quaternion, Basis, Transform2D/3D; an int blends to a float. Quaternions are normalized first. A Basis or Transform blends its rotation (slerp) and its per-axis scale (linearly) separately, so scaled ones blend too, however small the scale; shear is not kept. Other types, two samples of different types, a zero-length Quaternion or one whose squared length overflows, or a collapsed Basis or Transform (an axis of zero length, axes in one plane, or axes so long their volume overflows; vectors hold 32-bit floats, so about 1e19 is already too long) simply step from one value to the next. Samples that are not finite are refused at `add_sample` (see the API).
