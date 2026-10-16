# LFWobble

> A number that wobbles like a bobblehead's head: pushed by what its owner does, it lags, overshoots and settles.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_wobble.gd` |
| **Tests** | `tests/test_lf_wobble.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | nothing |

## When to use it

Use it for a part that should *look* as if it hung on a spring: a bobblehead, an antenna, a
hat, a tail, a hanging lamp, a button that jiggles when pressed. It is a damped spring worked
out in code, one number at a time, so it has no collider, no joint and no physics body, and it
can never push the thing it is attached to. For a value that eases to a target without
overshooting use `move_toward` or `LFRatchetFollow`; for a value that builds up and fades use `LFMomentum`;
for camera shake use `LFShaker`.

## Step by step

This makes a square that tilts when you drag it and wobbles back.

1. In the editor choose *Scene → New Scene*, click **2D Scene**, then attach a script to the
   root `Node2D` (right-click → *Attach Script* → *Create*).
2. Replace the script's text with this:

```gdscript
extends Node2D

var _tilt := LFWobble.new(160.0, 5.0)
var _last_x := 0.0
var _last_speed := 0.0

func _process(delta: float) -> void:
	var x := get_global_mouse_position().x
	var speed := (x - _last_x) / delta
	var acceleration := (speed - _last_speed) / delta
	_last_x = x
	_last_speed = speed
	# Push against the way the mouse speeds up, like a head left behind.
	_tilt.step(delta, -acceleration * 0.0005)
	queue_redraw()

func _draw() -> void:
	draw_set_transform(get_global_mouse_position(), _tilt.value)
	draw_rect(Rect2(-30.0, -30.0, 60.0, 60.0), Color.ORANGE)
```
3. Save and press **F6**. Shake the mouse left and right: the square tilts against the move,
   swings past upright and settles.
4. Change `160.0` (higher is stiffer and quicker) and `5.0` (higher settles sooner; lower wobbles longer).

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_STIFFNESS` | `const DEFAULT_STIFFNESS := 160.0` | Default pull back to rest. |
| `DEFAULT_DAMPING` | `const DEFAULT_DAMPING := 7.0` | Default slowdown. |
| `MAX_SLICE` | `const MAX_SLICE := 1.0 / 120.0` | A longer `delta` is simulated in slices this long. |
| `MAX_SLICES` | `const MAX_SLICES := 12` | The most slices one `step` simulates. |
| `_init` | `LFWobble.new(initial_stiffness := 160.0, initial_damping := 7.0)` | |
| `stiffness` | `var stiffness: float` | Pull back to 0, per second squared. |
| `damping` | `var damping: float` | Slowdown, per second. Wobbles while below `2 * sqrt(stiffness)`; at or above that it settles without overshooting. |
| `limit` | `var limit: float` | The value stays within `-limit` to `limit`; hitting it drops the speed. Default `INF`. |
| `value` | `var value: float` | Where it is now. |
| `velocity` | `var velocity: float` | How fast it is moving now. |
| `step` | `step(delta: float, drive := 0.0) -> float` | Moves on by `delta` seconds under a steady push `drive` and returns `value`. Does nothing for `delta <= 0` or a NaN. |
| `kick` | `kick(impulse: float)` | Adds to the speed: a hit. |
| `reset` | `reset()` | Back to rest at once. |

## Usage

A head that tilts against its body's sideways acceleration and bobs against its vertical one:

```gdscript
var _tilt := LFWobble.new(150.0, 6.0)
var _bob := LFWobble.new(220.0, 9.0)

func _physics_process(delta: float) -> void:
	var acceleration := (velocity - _last_velocity) / delta
	_last_velocity = velocity
	$Head.rotation.z = _tilt.step(delta, -acceleration.x * 0.02)
	$Head.position.y = _bob.step(delta, -acceleration.y * 0.01)
```

## Notes

- A steady `drive` holds the value at `drive / stiffness`; only a change in the push makes it swing. Feed it an acceleration, not a speed, to get a lag.
- Each wobble is one number. Use one per axis you want to move.
- A slow frame is cut into slices of at most `MAX_SLICE`, so a hitch does not make it explode; past `MAX_SLICES` slices the rest of the time is dropped.
