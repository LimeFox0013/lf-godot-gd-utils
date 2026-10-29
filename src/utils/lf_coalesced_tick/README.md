# LFCoalescedTick

> Runs a slow per-frame update that awaits, never twice at once, and banks the time of the frames it skipped.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_coalesced_tick.gd` |
| **Tests** | `tests/test_lf_coalesced_tick.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when your per-frame update can take more than one frame because it `await`s
something (a turn that waits for an animation, a network answer). Calling it again while it
is still running would run two copies; this runs one, and the frames in between add up their
time for the next run.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

# A step that takes about half a second to finish.
var _step := LFCoalescedTick.new(_slow_step)

func _slow_step(delta: float) -> void:
	print("step with ", snappedf(delta, 0.01), " seconds")
	await get_tree().create_timer(0.5).timeout

func _process(delta: float) -> void:
	_step.feed(delta)   # no await here
```

3. Press **F6**. Every half second or so the Output panel shows a step with about the time of the frames since the last one, never two steps at the same moment.

## API

| Member | Signature | Description |
|---|---|---|
| `tick_fn` | `var tick_fn: Callable` | The update, `tick_fn.call(delta: float)`; it may `await`. |
| `_init` | `LFCoalescedTick.new(update: Callable)` | Sets `tick_fn`. |
| `feed` | `feed(delta: float) -> void` | Banks `delta`; if idle, runs the update with all banked time and waits for it. Do not `await` it from the frame function. |
| `is_running` | `is_running() -> bool` | Whether the update is running now. |
| `pending_seconds` | `pending_seconds() -> float` | Seconds banked for the next run. |

## Usage

```gdscript
func _process(delta: float) -> void:
	_turns.feed(delta)   # _turns = LFCoalescedTick.new(_game.advance)
```

## Notes

- Time banked while the update runs is used by the next `feed` after it finishes; nothing runs on its own.
- If the update never finishes, it never runs again.
