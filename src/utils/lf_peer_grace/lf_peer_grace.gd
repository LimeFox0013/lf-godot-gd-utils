## Gives each newcomer a time limit to prove itself, and tells you who ran out.
##
## For a server where a connected peer must do something within N seconds (present a seat
## token, send a first message) or be let go. Call `add` when a peer connects, `proven`
## when it has done it, and `tick(delta)` every frame: it returns the peers that ran out of
## time. It disconnects no one itself; you act on the list.
class_name LFPeerGrace
extends RefCounted

## Default seconds a peer has.
const DEFAULT_GRACE_SECONDS := 5.0

## Seconds a peer has, counted from `add`. Applies to peers already waiting.
var grace_seconds: float
## `peer -> seconds waited`, in the order the peers were added.
var _waited: Dictionary = {}


func _init(grace := DEFAULT_GRACE_SECONDS) -> void:
	grace_seconds = grace


## Starts the clock for `peer`; a peer already waiting starts over.
func add(peer: Variant) -> void:
	_waited[peer] = 0.0


## `peer` proved itself: stops its clock. Does nothing for a peer that is not waiting.
func proven(peer: Variant) -> void:
	_waited.erase(peer)


## Stops `peer`'s clock because it left; the same as `proven`.
func forget(peer: Variant) -> void:
	_waited.erase(peer)


## Whether `peer` is still waiting to prove itself.
func is_pending(peer: Variant) -> bool:
	return _waited.has(peer)


## The number of peers still waiting.
func pending_count() -> int:
	return _waited.size()


## Advances every waiting clock by `delta` seconds. Returns, in the order they were added,
## the peers whose time is up (`grace_seconds` or more); they are no longer waiting.
func tick(delta: float) -> Array:
	var expired := []
	for peer in _waited.keys():
		_waited[peer] += delta
		if _waited[peer] >= grace_seconds:
			expired.append(peer)
	for peer in expired:
		_waited.erase(peer)
	return expired
