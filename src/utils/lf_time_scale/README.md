# LFTimeScale

> A short slow-motion pulse measured in real seconds: the game slows for a moment, then runs at the speed it had.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it as `LFTimeScale.pulse(...)` |
| **Files** | `lf_time_scale.gd` |
| **Tests** | `tests/test_lf_time_scale.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it to dwell on a moment: the last hit of a fight, the winning jump, a near miss. It changes `Engine.time_scale`, so
everything that runs on game time slows, including timers made with `create_timer` unless they ignore the time scale.

## Step by step

1. Add a node to your scene, attach a script and replace its text with the code below.
2. Press **F6**. A ball moves across the window at normal speed, slows down for a moment after one second, and speeds up again.

```gdscript
extends Node2D

var x := 0.0


func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	LFTimeScale.pulse(get_tree(), 0.2, 0.8)


func _process(delta: float) -> void:
	x += 300.0 * delta
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(fmod(x, 1000.0), 200.0), 20.0, Color.ORANGE)
```

## API

| Member | Signature | Description |
|---|---|---|
| `pulse` | `static pulse(tree: SceneTree, scale: float, real_seconds: float) -> void` | Sets the speed to `scale` (at least `MIN_SCALE`) for `real_seconds` of real time, then restores the speed from before. A new pulse takes over a running one. Nothing for a null tree. |
| `reset` | `static reset() -> void` | Puts the speed back now and ends any pulse. |
| `is_active` | `static is_active() -> bool` | Whether a pulse is on. |
| `MIN_SCALE` | `0.01` | The slowest a pulse can go. |

## Notes

- Call `reset()` when the scene that pulsed is freed, or a restart in the middle of a pulse runs in slow motion until its timer ends.
- A pulse also ends, and the speed comes back, when the tree's root window starts leaving the tree (quit, or the tree being freed). This is done by listening to the root's `tree_exiting` signal; a tree without a root is not watched. If something frees the tree without that signal firing, call `reset()` yourself.
- Anything else that sets `Engine.time_scale` during a pulse is overwritten when the pulse ends.
