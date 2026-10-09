# LFCooldown

> A cooldown: an action may run again only once an interval has passed since its last use.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_cooldown.gd` |
| **Tests** | `tests/test_lf_cooldown.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to stop an action from repeating too fast: a dash ability that can be used once
every 1.5 s, a gun's fire rate, a "you can only send a chat message every 2 s" limit. You
ask it "may this run now?" (`is_ready()` or `try_use()`); nothing runs on its own and no
node or timer is needed. To *delay* a call until things go quiet use `LFDebounce`; to cap
a callback's rate while still delivering the last call use `LFThrottle`; for something
that fires every N seconds by itself use `LFIntervalTimer` or a Godot `Timer` node.

## Step by step

A cooldown answers one question: "has enough time passed since the last use?"

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

# One use allowed every 1500 milliseconds (1.5 seconds).
var _dash := LFCooldown.new(1500)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):   # Space or Enter
		# try_use() returns true and starts the wait if it was ready; otherwise false.
		if _dash.try_use():
			print("Dash!")
		else:
			print("Not ready yet, wait %d ms" % _dash.remaining_ms())
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. Press *Space* or *Enter* in the running window. The first press prints `Dash!`.
   Pressing again straight away prints `Not ready yet, wait ...` with the milliseconds
   left; after 1.5 s it prints `Dash!` again.
6. Change `1500` to your own wait in milliseconds. Put your real action (move the player,
   fire the gun) where `print("Dash!")` is.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFCooldown.new(initial_interval_ms: float, initial_clock_ms := Callable())` | Ready before its first use. Doesn't read the clock. Without `initial_clock_ms` it runs on `Time.get_ticks_msec()`; with it (stored as `clock_ms`), `clock_ms.call()` must return the current time in milliseconds (an int or a float). |
| `interval_ms` | `var interval_ms: float` | Milliseconds between uses; 0 or less: always ready; `INF`: never ready after a use. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept (0 right after construction). May change at any time; every check reads it. |
| `is_ready` | `is_ready() -> bool` | Whether a use would pass now. Never changes the cooldown. |
| `try_use` | `try_use() -> bool` | If ready, starts a new interval and returns `true`; otherwise returns `false` and changes nothing. |
| `start` | `start() -> void` | Starts a new interval now, ready or not. |
| `clock_ms` | `var clock_ms: Callable` | Returns now in milliseconds as an int or a float; empty: `Time.get_ticks_msec()`. Replaceable at any time. |
| `reset` | `reset() -> void` | Ready immediately (not to be confused with `LFIntervalTimer.restart`, which starts the wait over). |
| `remaining_ms` | `remaining_ms() -> float` | Milliseconds until ready; 0.0 when ready. |

## Usage

```gdscript
# player.gd — on the player's CharacterBody2D
extends CharacterBody2D

var _dash := LFCooldown.new(1500)   # one dash every 1.5 s (wall clock)

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") and _dash.try_use():
		velocity.x += 600.0          # dash!
	move_and_slide()

func dash_label_text() -> String:
	# e.g. "1.2 s" on the ability button, "" when ready
	var left := _dash.remaining_ms()
	return "" if left == 0.0 else "%.1f s" % (left / 1000.0)
```

On a simulation's own clock (paused, sped up, replayed), pass a method returning ms. This is part of a script that also has its own `_target_in_range()` and `_cast()` methods, and advances `_world_ms` itself:

```gdscript
var _world_ms := 0

func _world_now() -> int:
	return _world_ms

var _ability := LFCooldown.new(5000, _world_now)

func _on_attack_requested() -> void:
	if _ability.is_ready() and _target_in_range():   # check other conditions first
		_ability.start()                              # then spend the cooldown
		_cast()
```

## Notes

- `is_ready()` then `start()` lets a caller check other conditions in between (a chance
  roll, a range check) and only spend the cooldown when the action really happens.
  `try_use()` is the same in one call.
- With a clock you supplied (the optional second argument, `initial_clock_ms`), only that clock readies the cooldown; real time is ignored.
  A clock that reads earlier than the last use (rewound or reset) counts as elapsed.
- A supplied clock that can no longer be called (its object was freed) keeps the
  cooldown closed and reports one error. It never falls back to the wall clock:
  `remaining_ms()` then returns the full `interval_ms`, and `start()` does nothing.
- One instance is one cooldown. Share an instance only if the cooldown should be shared.
- The default clock (real time) ignores `Engine.time_scale` and pausing, like `LFThrottle`/`LFDebounce`.
  For a cooldown that pauses with the game, pass a clock that only advances while it runs.
