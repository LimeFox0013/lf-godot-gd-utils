# LFInputBuffer

> Keeps a press for a short moment so a later event can still use it, and tells you once if nobody did.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_input_buffer.gd` |
| **Tests** | `tests/test_lf_input_buffer.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it when a button press should still count a moment later: a jump pressed just before the
character lands, an attack pressed just before the previous one ends. It only keeps the
press and its clock; you decide what taking it does. Its time is the `delta` you pass.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

   ```gdscript
   extends Node

   var _jump := LFInputBuffer.new(0.1)   # a press is kept for 0.1 seconds
   var _on_floor := false


   func _process(delta: float) -> void:
   	if Input.is_action_just_pressed("ui_accept"):
   		_jump.press()
   	if _on_floor and _jump.take():
   		print("jump!")
   	if _jump.tick(delta):
   		print("the press was too early, nothing used it")
   ```
3. Press **F6**. Press **Space** while `_on_floor` is false: after 0.1 seconds the message appears once. Set `_on_floor = true` within that time and the jump happens instead.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_WINDOW` | `const := 0.08` | Default seconds a press is kept. |
| `new` | `LFInputBuffer.new(window := DEFAULT_WINDOW)` | A window of 0 or less, NaN or infinite is reported through `LFLogger` and the default is used. |
| `window` | `var window: float` | Seconds a press is kept. Read only. |
| `pending` | `var pending: bool` | Whether a press is waiting. Read only. |
| `age` | `var age: float` | Seconds since the pending press (0 when none waits), so the one who takes it can grade it by how long ago it was made. Read only. |
| `press` | `press() -> void` | Marks a press pending and restarts the window. |
| `take` | `take() -> bool` | True once while a press is pending; clears it. |
| `tick` | `tick(delta: float) -> bool` | Ages a pending press; true on the one call where the window runs out unused. A negative or NaN `delta` changes nothing. |
| `clear` | `clear() -> void` | Drops a pending press without an expiry report. |

## Usage

A combo attack: a press during the last 0.15 seconds of a swing still starts the next one. Add this to a script that has its own `_start_swing()` method; call `_swing_ended()` when a swing finishes.

```gdscript
var _attack := LFInputBuffer.new(0.15)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		_attack.press()
	_attack.tick(delta)

func _swing_ended() -> void:
	if _attack.take():
		_start_swing()   # the press was made shortly before the swing ended
```

`age` tells the one who takes a press how long ago it was made, so the take can be graded:

```gdscript
var how_early := _attack.age   # read it before take(), which clears the press
if _attack.take():
	print("pressed %.2f s ago" % how_early)
```

## Notes

- Expiry is reported once; after it the press is no longer pending.
- A `take` before the window runs out cancels the expiry report.
- `age` reads 0 once the press is taken, cleared or expired.
- A press arriving while one is pending restarts the window rather than queueing a second one.
