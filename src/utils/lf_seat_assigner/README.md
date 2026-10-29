# LFSeatAssigner

> Hands out a fixed set of seats to connecting players in order, and lets a player claim a specific seat.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_seat_assigner.gd` |
| **Tests** | `tests/test_lf_seat_assigner.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it on a server with a fixed number of places (teams, colours, slots) where each
connecting player gets the next free one, or asks for a particular one and swaps with
whoever has it. It keeps no sockets: you call it when someone connects or leaves.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

func _ready() -> void:
	var seats := LFSeatAssigner.new(["red", "blue"])
	seats.seat_assigned.connect(func(peer, seat): print("peer ", peer, " plays ", seat))
	seats.assign_next(10)   # peer 10 connects
	seats.assign_next(11)   # peer 11 connects
	seats.move(10, "blue")  # peer 10 asks for blue: the two swap
```

3. Press **F6**. The Output panel shows peer 10 on red, peer 11 on blue, then peer 11 on red and peer 10 on blue.

## API

| Member | Signature | Description |
|---|---|---|
| `seat_assigned` | `signal seat_assigned(peer, seat)` | A peer now holds a seat; on a swap the displaced peer comes first. |
| `_init` | `LFSeatAssigner.new(seats := [])` | The seats, in the order they are handed out. |
| `reserve` | `reserve(seat) -> void` | Takes a seat out of the pool; a peer can still `move` onto it. |
| `assign_next` | `assign_next(peer) -> bool` | Seats the peer on the first free seat; false when none is free or the peer already holds a seat. |
| `move` | `move(peer, seat) -> bool` | Moves a seated peer onto a seat, swapping with its holder. False for an unseated peer or an unknown seat. |
| `forget` | `forget(peer) -> Variant` | Removes the peer and its proof, frees its seat at the back of the line and returns it (null for an unseated peer). |
| `seat_of` / `peer_of` | `seat_of(peer)` / `peer_of(seat)` | The seat a peer holds / the peer holding a seat; null when none. |
| `has_peer` | `has_peer(peer) -> bool` | Whether the peer holds a seat. |
| `peers` / `seats_by_peer` | `peers() -> Array` / `seats_by_peer() -> Dictionary` | Seated peers / a copy of `peer -> seat`. |
| `assigned_count` | `assigned_count() -> int` | How many peers hold a seat. |
| `is_free` / `free_seats` | `is_free(seat) -> bool` / `free_seats() -> Array` | Whether a seat is in the pool / a copy of the pool in hand-out order. |
| `mark_verified` | `mark_verified(peer) -> void` | Records that a seated peer proved its seat. |
| `is_verified` / `verified_count` | `is_verified(peer) -> bool` / `verified_count() -> int` | Who proved their seat. |

## Usage

```gdscript
func _on_peer_connected(peer_id: int) -> void:
	if not _seats.assign_next(peer_id):
		disconnect_peer(peer_id)   # every seat is taken
```

## Notes

- A freed seat goes to the back of the line, so the next newcomer gets the seat that has been free longest.
- A `move` to an unknown seat fails, even if the seat is free.
- Seats and peers are compared with `==` and used as dictionary keys.
- `forget` puts the seat back in the pool even if it was `reserve`d.
