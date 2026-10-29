## The client side of `LFSnapshotReplicator`: keeps the newest state, replaced by each
## checkpoint and changed by each delta.
##
## A delta that arrives before any checkpoint has nothing to apply to, so it is ignored.
## The snapshot type and how a delta applies to it are up to the caller (`apply_delta_fn`).
class_name LFSnapshotReceiver
extends RefCounted

## `(snapshot, delta) -> Variant`: the snapshot with the delta applied.
var apply_delta_fn: Callable
## The newest state, or null before the first checkpoint.
var current: Variant = null


func _init(delta_applier: Callable = Callable()) -> void:
	apply_delta_fn = delta_applier


## Replaces the state with a full `snapshot`.
func on_checkpoint(snapshot: Variant) -> void:
	current = snapshot


## Applies `delta` to the state and returns true; false (and no change) before any checkpoint.
func on_delta(delta: Variant) -> bool:
	if current == null or not apply_delta_fn.is_valid():
		return false
	current = apply_delta_fn.call(current, delta)
	return true
