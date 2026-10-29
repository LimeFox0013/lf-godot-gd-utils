## Hands out a fixed set of seats to connecting peers, in order, and lets a peer claim a
## specific seat (swapping with whoever holds it).
##
## Seats and peers are any values you choose (a team name, a colour, a slot number; a peer
## id). It keeps no sockets: you call it when a peer connects or leaves and act on
## `seat_assigned`. It also remembers which seated peers have proven their seat.
class_name LFSeatAssigner
extends RefCounted

## A peer now holds `seat`: a first assignment, or either side of a swap (the displaced peer first).
signal seat_assigned(peer: Variant, seat: Variant)

## `peer -> seat`, in the order the peers were first seated.
var _seat_of_peer: Dictionary = {}
var _known: Dictionary = {}
var _free: Array = []
var _verified: Dictionary = {}


func _init(seats: Array = []) -> void:
	for seat in seats:
		_known[seat] = true
	_free = seats.duplicate()


## Takes `seat` out of the pool new peers draw from; a peer can still `move` onto it.
func reserve(seat: Variant) -> void:
	_free.erase(seat)


## Seats the next free seat to `peer` and emits `seat_assigned`. False, changing nothing,
## when none is free or `peer` already holds a seat.
func assign_next(peer: Variant) -> bool:
	if _seat_of_peer.has(peer) or _free.is_empty():
		return false
	var seat: Variant = _free.pop_front()
	_seat_of_peer[peer] = seat
	seat_assigned.emit(peer, seat)
	return true


## Moves a seated `peer` onto `seat`. If another peer holds it the two swap, otherwise the
## old seat goes to the back of the free list. False, changing nothing, for an unseated
## peer or a seat the assigner was not made with.
func move(peer: Variant, seat: Variant) -> bool:
	if not _seat_of_peer.has(peer) or not _known.has(seat):
		return false
	var old_seat: Variant = _seat_of_peer[peer]
	if old_seat == seat:
		return true
	var displaced: Variant = peer_of(seat)
	_seat_of_peer[peer] = seat
	if displaced != null:
		_seat_of_peer[displaced] = old_seat
		seat_assigned.emit(displaced, old_seat)
	else:
		_free.erase(seat)
		_free.append(old_seat)
	seat_assigned.emit(peer, seat)
	return true


## Removes `peer` and its proof; its seat goes to the back of the free list and is
## returned. Null, changing nothing else, for an unseated peer.
func forget(peer: Variant) -> Variant:
	_verified.erase(peer)
	if not _seat_of_peer.has(peer):
		return null
	var seat: Variant = _seat_of_peer[peer]
	_seat_of_peer.erase(peer)
	_free.append(seat)
	return seat


## The seat `peer` holds, or null.
func seat_of(peer: Variant) -> Variant:
	return _seat_of_peer.get(peer)


## The peer holding `seat`, or null.
func peer_of(seat: Variant) -> Variant:
	return _seat_of_peer.find_key(seat)


## Whether `peer` holds a seat.
func has_peer(peer: Variant) -> bool:
	return _seat_of_peer.has(peer)


## Every seated peer, in the order they were first seated.
func peers() -> Array:
	return _seat_of_peer.keys()


## A copy of `peer -> seat`.
func seats_by_peer() -> Dictionary:
	return _seat_of_peer.duplicate()


## How many peers hold a seat.
func assigned_count() -> int:
	return _seat_of_peer.size()


## Whether `seat` is in the pool the next peer draws from (nobody holds it, not reserved).
func is_free(seat: Variant) -> bool:
	return _free.has(seat)


## A copy of the free seats, in the order they will be handed out.
func free_seats() -> Array:
	return _free.duplicate()


## Records that a seated `peer` proved its seat. Ignored for an unseated peer.
func mark_verified(peer: Variant) -> void:
	if _seat_of_peer.has(peer):
		_verified[peer] = true


## Whether `peer` proved its seat and still holds one.
func is_verified(peer: Variant) -> bool:
	return _verified.has(peer)


## How many seated peers proved their seat.
func verified_count() -> int:
	return _verified.size()
