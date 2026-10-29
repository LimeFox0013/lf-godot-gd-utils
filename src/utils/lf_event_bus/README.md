# LFEventBus

> Game-wide named events: any script can send one or listen for one, with no node or autoload to set up.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_event_bus.gd` |
| **Tests** | `tests/test_lf_event_bus.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFEventEmitter`, `LFLogger` |

## When to use it

Use it when scripts that don't know about each other need to talk: every enemy emits
`"enemy-killed"` and the score label, the achievement tracker and the music manager all
listen, without the enemy holding a reference to any of them. It is the "global signal
bus" pattern, without having to create an autoload scene. Because it lives for the whole
game, prefer an `LFEventEmitter` owned by a level or unit when the events belong to that
object, and plain Godot signals between a parent and its children.

## Step by step

The bus is shared by the whole game, so two scripts can talk without knowing about
each other. This example makes one node send an event and another node listen.

1. In the editor choose *Scene → New Scene*. In the Scene dock click *Other Node*, pick
   *Node*, press *Create*. Rename it `Main` (select it and press *F2*).
2. Click *+ Add Child Node*, pick *Node*, press *Create*, and rename it `Listener`.
3. Right-click `Listener`, choose *Attach Script*, keep the defaults, press *Create*, and
   replace the script with:

```gdscript
extends Node

func _ready() -> void:
	# "Call _on_coin whenever someone announces 'coin-collected'."
	LFEventBus.on("coin-collected", _on_coin)

func _exit_tree() -> void:
	# Stop listening when this node leaves the game.
	LFEventBus.off("coin-collected", _on_coin)

func _on_coin(amount: int) -> void:
	print("Got ", amount, " coins")
```
4. Right-click `Main`, choose *Attach Script*, keep the defaults, press *Create*, and
   replace the script with:

```gdscript
extends Node

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):   # Space or Enter
		# Announce the event, with one value (5) for the listeners.
		LFEventBus.emit_sync("coin-collected", 5)
```
5. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
6. Press *Space* or *Enter* in the running window. The *Output* panel should show
   `Got 5 coins` each time. Neither script refers to the other; only the event name
   `"coin-collected"` connects them.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `emitter` | `static var emitter: LFEventEmitter` | The shared emitter, for `emit`, `has_handlers` and `handler_count`. Read-only (assigning reports an error). |
| `emit_sync` | `static emit_sync(event: String, ...args: Array) -> void` | Calls every handler right away. To await async handlers: `await LFEventBus.emitter.emit(...)`. |
| `emit_sync_v` | `static emit_sync_v(event: String, args: Array) -> void` | `emit_sync` with the arguments in an array. |
| `on` | `static on(event: String, cb: Callable) -> void` | Registers `cb` (twice registered, twice called). |
| `once` | `static once(event: String, cb: Callable) -> void` | Runs `cb` on the next emit only. |
| `off` | `static off(event: String, cb: Callable) -> void` | Removes the first registration of `cb`; an empty `Callable()` removes nothing and is reported as an error; use `clear_event`. |
| `off_owner` | `static off_owner(owner: Object) -> int` | Removes every handler `owner` registered through `on`/`once` (a method of it, or a lambda in one of its methods that uses `self`), on all events; returns how many it removed. See Notes. |
| `clear_event` | `static clear_event(event: String) -> void` | Removes every handler of `event`. |
| `clear` | `static clear() -> void` | Removes every handler of every event; reset between tests or scenes. |

## Usage

```gdscript
# score_label.gd — on the HUD's Label
extends Label

var score := 0

func _ready() -> void:
	LFEventBus.on("enemy-killed", _on_enemy_killed)

func _exit_tree() -> void:
	LFEventBus.off("enemy-killed", _on_enemy_killed)   # always unsubscribe when leaving

func _on_enemy_killed(points: int) -> void:
	score += points
	text = str(score)
```

This is part of an enemy's script, which extends a node type (e.g. `CharacterBody2D`), so `queue_free()` exists:

```gdscript
# enemy.gd — any enemy, anywhere in the tree
func die() -> void:
	LFEventBus.emit_sync("enemy-killed", 10)
	queue_free()
```

## Notes

- Game-wide: everything registered stays until removed or `clear()`. Prefer an `LFEventEmitter` owned by whatever has the lifetime you need (a level, a scene).
- Registering a method (like `_on_coin` above) does not keep its node alive. When the node
  is freed its registration stays on the bus, doing nothing when the event is emitted,
  until you remove it with `off` or call `clear()`, so remove a node's handlers in
  `_exit_tree()`, as above. An inline `func(): ...` handler keeps the reference-counted
  values it captures (Resources, RefCounted objects) alive while it is registered.
- `off_owner(owner)` is for handlers you cannot name again, such as `LFEventBus.on("x", func(): refresh())` written in a method (a lambda that uses `self` belongs to that `self`). One call in `_exit_tree()` removes everything the object registered, on every event. It finds handlers by the object their Callable is bound to (`Callable.get_object()`), and only among those registered through `LFEventBus.on`/`once`: a lambda written in a static function has no object, and `LFEventBus.emitter.on(...)` is not tracked. The bus keeps a small note per registration for this; `off`, `clear_event` and `clear` drop the matching notes, a one-shot's note stays until `off_owner` or `clear()` (it is not counted once fired), and notes of owners that were freed are swept as new owners register. Registrations themselves are unchanged: a freed owner's handlers still stay on the bus, inert, until removed or `clear()`; pass the owner to `off_owner` while it is alive (it cannot be passed once freed).
- Pick event names once and reuse them (a `const` per name avoids typos: a misspelled name just has no listeners).
