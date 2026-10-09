# LFEventEmitter

> Named events that any code can listen to, owned by one object; `emit` can await every (possibly async) handler.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_event_emitter.gd` |
| **Tests** | `tests/test_lf_event_emitter.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFAwait` |

## When to use it

Use it when an object (a level, a unit, an inventory) should announce things by name and
let any number of listeners react: `inventory.events.emit_sync("item-added", item)` with
the HUD, the sound system and a quest tracker all listening. Event names are plain
strings, so nothing has to be declared up front, and `emit` can wait for listeners that
themselves `await` (play a death animation before the unit is removed). For a fixed set
of events on one class, Godot's built-in `signal` is simpler and type-checked; for events
the whole game shares without passing an object around, use `LFEventBus`.

## Step by step

An emitter lets one object announce named events ("greeted", "died") and any other
code listen for them. Events are just text names; you declare nothing in advance.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

# The emitter belongs to this node. Keep it in a variable.
var events := LFEventEmitter.new()

func _ready() -> void:
	# Whenever "greeted" is announced, call _on_greeted.
	events.on("greeted", _on_greeted)

	# emit_sync: call every listener right now and carry on.
	events.emit_sync("greeted", "Ann")

	# emit: call every listener AND wait for each one to finish (`await` = wait here).
	await events.emit("greeted", "Bob")
	print("All listeners are done")

# A listener. It receives the values that were sent with the event.
func _on_greeted(who: String) -> void:
	print("Hello, ", who)
	await get_tree().create_timer(0.5).timeout   # pretend to do something for half a second
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. In the *Output* panel you should see `Hello, Ann`, `Hello, Bob`, and then, half a
   second after Bob's greeting, `All listeners are done`. (`emit_sync` did not wait for
   Ann's listener; `emit` waited for Bob's.)
6. Pick your own event names and send whatever values you like after the name:
   `events.emit_sync("died", unit, 10)`. Every listener must accept exactly that many
   values.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `emit` | `emit(event: String, ...args: Array) -> Array` | Coroutine. Awaits every handler registered when it started; resolves with their results in registration order (`[]` with none; `null` for one removed before its turn). |
| `emit_sync` | `emit_sync(event: String, ...args: Array) -> void` | Calls every handler right away; an async handler is started, not awaited. |
| `emit_sync_v` | `emit_sync_v(event: String, args: Array) -> void` | `emit_sync` with the arguments in an array. |
| `on` | `on(event: String, cb: Callable) -> void` | Registers `cb` (twice registered, twice called). |
| `once` | `once(event: String, cb: Callable) -> void` | Runs `cb` on the next emit only; deregistered before it runs. |
| `off` | `off(event: String, cb: Callable) -> void` | Removes the first registration of `cb` (by `on` or `once`); an empty `Callable()` removes nothing and is reported as an error; use `clear_event`. |
| `clear_event` | `clear_event(event: String) -> void` | Removes every handler of `event` (pending `once`s included). |
| `clear` | `clear() -> void` | Removes every handler of every event. |
| `has_handlers` | `has_handlers(event: String) -> bool` | Whether `event` has any handler. |
| `handler_count` | `handler_count(event: String) -> int` | Its registrations; a callback registered twice counts twice. |

## Usage

```gdscript
# unit.gd — on each unit
extends Node2D

var events := LFEventEmitter.new()

func die() -> void:
	# Wait for every listener, including ones that play an animation first.
	await events.emit("died", self)
	queue_free()
```

```gdscript
# hud.gd — listens to a unit it was given
extends Control

var kills := 0

func watch(unit: Node2D) -> void:
	unit.events.on("died", _on_unit_died)
	unit.events.once("died", func(_u: Node2D): print("first blood!"))

func _on_unit_died(_unit: Node2D) -> void:
	kills += 1
	await get_tree().create_timer(0.3).timeout   # the unit waits for this too
```

## Notes

- The handlers an emit calls are the ones registered when it started: one added during it waits for the next emit; one removed or cleared before its turn is skipped. Re-emitting, registering and clearing from inside a handler work as described here (tests cover them).
- A pending `once` doesn't keep the emitter itself alive (unless the handler you passed holds a reference to the emitter).
- A handler that stops with a script error (Godot reports it) gives `null` in its result slot; `emit` still resolves. A handler that never finishes awaiting keeps `emit` waiting.
- Registering a method does not keep its object alive. A handler whose object was freed
  stays registered (it counts in `handler_count`) until `off` or `clear`, and does nothing
  when emitted (`emit` gives it a `null` slot). An inline `func(): ...` handler keeps the
  reference-counted values it captures alive while it is registered.
- Use it from the main thread only.
- `off` is O(handlers of that event).
- A handler must accept the arguments the event is emitted with (same count); otherwise Godot reports an error for that call.
