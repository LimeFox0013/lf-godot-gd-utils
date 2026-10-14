# LFPeerGrace

> Gives each newcomer a time limit to prove itself, and tells you who ran out.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_peer_grace.gd` |
| **Tests** | `tests/test_lf_peer_grace.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it on a server where a connected player must do something soon, such as show a seat
token or send a first message, or be let go. It only keeps the clocks; you disconnect the
peers it names. Its time is the `delta` you pass, so it follows your game's clock.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

var _grace := LFPeerGrace.new(2.0)

func _ready() -> void:
	_grace.add(7)   # peer 7 just connected

func _process(delta: float) -> void:
	for peer in _grace.tick(delta):
		print("peer ", peer, " did not prove itself in time")
```

3. Press **F6**. After about two seconds the Output panel shows the message once.
4. Call `_grace.proven(7)` when the peer proves itself, and it is never named.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_GRACE_SECONDS` | `const := 5.0` | Default `grace_seconds`. |
| `grace_seconds` | `var grace_seconds: float` | Seconds a peer has from `add`. |
| `_init` | `LFPeerGrace.new(grace := DEFAULT_GRACE_SECONDS)` | Sets `grace_seconds`. |
| `add` | `add(peer: Variant) -> void` | Starts the clock; a peer already waiting starts over. |
| `proven` | `proven(peer: Variant) -> void` | Stops the clock. Nothing happens for a peer not waiting. |
| `forget` | `forget(peer: Variant) -> void` | Stops the clock of a peer that left (the same as `proven`). |
| `is_pending` | `is_pending(peer: Variant) -> bool` | Whether `peer` is still waiting. |
| `pending_count` | `pending_count() -> int` | How many peers are waiting. |
| `tick` | `tick(delta: float) -> Array` | Advances every clock; returns the peers at `grace_seconds` or more, in the order added. They stop waiting. |

## Usage

```gdscript
func _on_peer_connected(peer_id: int) -> void:
	_grace.add(peer_id)

func _on_seat_token_ok(peer_id: int) -> void:
	_grace.proven(peer_id)

func _process(delta: float) -> void:
	for peer_id in _grace.tick(delta):
		_server.disconnect_peer(peer_id)
```

## Notes

- A peer is named once; after that it is no longer waiting.
- It never touches the connection: pair it with `LFSocketServer.disconnect_peer`.
