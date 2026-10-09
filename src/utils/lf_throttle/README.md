# LFThrottle

> Limits how often a callback runs, however often it is called, with optional leading-edge and trailing-edge runs.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_throttle.gd` |
| **Tests** | `tests/test_lf_throttle.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`create_timer`), `LFLogger` |

## When to use it

Use it when a callback is called far more often than it needs to run: update a drag
preview at most every 100 ms while the mouse moves every frame, send a player's position
to the server 10 times a second, play a footstep sound no faster than every 250 ms. The
first call runs at once (leading edge); with `trailing` on, the last call of a busy window
also runs when the window ends, so the final state is delivered (unless you `cancel()` or
the throttle is freed first). To wait until calls stop
and run only the last one use `LFDebounce`; for a yes/no "may this run now?" gate with no
deferred call use `LFCooldown`.

## Step by step

A *throttle* limits how often a function runs, however often you call it. Here the
code asks to run every frame, but the throttle lets it through only twice a second.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

# Let _report run at most once every 500 milliseconds.
# Keep it in a variable like this so it stays alive.
var _throttled := LFThrottle.new(_report, 500)

func _process(_delta: float) -> void:
	# _process runs every frame (about 60 times a second).
	_throttled.trigger(Engine.get_frames_drawn())   # extra values are passed to _report

func _report(frame: int) -> void:
	print("ran on frame ", frame)
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. In the *Output* panel a new line should appear about every half second (the frame
   number grows by roughly 30 each time), even though `trigger` is called every frame.
   The first call runs immediately.
6. Change `500` to your interval in milliseconds. Add two more values to also run the
   last skipped call when the window ends: `LFThrottle.new(_report, 500, true, true)`
   (`true` for "run the first call at once", `true` for "run the last call at the end").

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_INTERVAL_MS` | `const float = 1000.0 / 60` (ms) | Default `interval_ms`: one 60 fps frame (about 16.7 ms). |
| `_init` | `LFThrottle.new(callback: Callable, initial_interval_ms: float = DEFAULT_INTERVAL_MS, run_leading := true, run_trailing := false)` | `initial_interval_ms` (milliseconds) becomes `interval_ms`. Both edges off is reported through `LFLogger` (an error, no `assert`); the throttle then never runs until an edge is switched on. |
| `interval_ms` | `var interval_ms: float` | Window length in real milliseconds. A NaN is rejected: reported through `LFLogger` as an error, and the value is kept. |
| `leading` | `var leading: bool` | Run the call that opens a window at once. |
| `trailing` | `var trailing: bool` | Run the latest undelivered call when the window ends. |
| `trigger` | `trigger(...args: Array) -> void` | A call through the throttle. A call `interval_ms` or more after the window opened opens a new one: with `leading` it runs now (and clears any pending call), otherwise it becomes pending. A call inside a window becomes pending with `trailing`, and is dropped without it. A pending call runs with the latest args when the window ends — waiting out a window a leading run moved, or a longer `interval_ms` set meanwhile. |
| `is_pending` | `is_pending() -> bool` | A trailing call is waiting (always false with `trailing` off). |
| `cancel` | `cancel() -> void` | Drops the waiting trailing call. |
| `flush` | `flush() -> void` | Runs the waiting trailing call now (opening a new window); a no-op when nothing waits. |
| `fn` | `static fn(callback: Callable, initial_interval_ms: float = DEFAULT_INTERVAL_MS, run_leading := true, run_trailing := false) -> Callable` | A Callable taking any arguments that calls a new throttle's `trigger`. |

## Usage

```gdscript
# level_editor.gd — on the editor's root Node2D
extends Node2D

# Leading + trailing: the first mouse move redraws at once, then at most every 100 ms,
# and the last position of a fast drag is always drawn when the window ends.
var _redraw := LFThrottle.new(_update_preview, 100, true, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_redraw.trigger(event.position)

func _update_preview(at: Vector2) -> void:
	$Preview.position = at

func _exit_tree() -> void:
	_redraw.cancel()   # don't redraw after the editor closes
```

The one-line form, leading edge only (calls inside a window are dropped). These lines go inside a function of a node's script whose node has a `StepSound` child (an audio player):

```gdscript
var footstep := LFThrottle.fn(func(): $StepSound.play(), 250)
footstep.call()   # plays
footstep.call()   # dropped: within 250 ms of the last one
```

## Notes

- `interval_ms` is **real time**: it ignores `Engine.time_scale` (slow motion) and keeps counting while the game is paused. It needs a running game (a scene tree). `LFDebounce` does the same.
- Runs through `trigger` are never closer than `interval_ms`, even when called every frame.
  `flush()` is the exception: it runs the waiting call at once and opens a new window from there.
- Times are read from `Time.get_ticks_msec()` (whole milliseconds), and the trailing run
  waits on a timer, so it lands on the first frame after the window ends, not exactly at its end.
- "Leading" is the call that opens a window; "trailing" is the last call, run when the window ends. The trailing run only happens for a call the leading run didn't deliver, so a lone call runs once.
- A callback whose object was freed is skipped (no error).
- With `trailing` off (leading only), calls inside a window are dropped outright: nothing is kept, so `flush()` never delivers them.
- Setting `leading` and `trailing` both to false after construction silently disables the throttle (only the constructor reports it).
- Keep the instance in a variable that outlives the calls (a member, as above): a throttle nobody references is freed, and its waiting trailing call never runs. `fn()`'s Callable keeps its own throttle alive.
