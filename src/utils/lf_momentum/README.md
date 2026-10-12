# LFMomentum

> A value that bumps build up and that wears off down to a base while you say it is slowing.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_momentum.gd` |
| **Tests** | `tests/test_lf_momentum.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for a number that rewards a streak and forgets it when the player stops: a runner's
acceleration that grows with every good jump and fades while the runner slows down, a
"heat" that builds while attacking, a charge that drains when released. You `bump` it on
the good event, call `step(delta, slowing)` every frame, and `penalize` it on a mistake.
`ratio()` turns it into 0 to 1 for a bar or for another system. For a stack of graded
results use `LFGradeCombo`; for a plain value that moves toward a target use Godot's
`move_toward`; for timed bonuses use `LFStatusEffects`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node

   # Rests at 10, can grow to 30, loses 4 per second while slowing.
   var acceleration := LFMomentum.new(10.0, 30.0, 4.0)


   func _ready() -> void:
   	acceleration.bump(8.0)
   	print("after a good jump: ", acceleration.value)          # 18
   	print("one second of slowing: ", acceleration.step(1.0, true))   # 14
   	print("one second not slowing: ", acceleration.step(1.0, false)) # 14, nothing wears off
   	print("a miss costs 25 %: ", acceleration.penalize(0.25))        # 10.5
   	print("how built up: ", acceleration.ratio())                    # 0.025
   ```
4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
5. In the *Output* panel you should see the five lines with the numbers in the comments.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `new` | `LFMomentum.new(initial_base: float = 0.0, initial_cap: float = CAP_AT_BASE, initial_decay_per_second: float = DEFAULT_DECAY_PER_SECOND)` | Rests at the base. A cap below the base is reported through `LFLogger` and the base is used; `CAP_AT_BASE` (NaN) means the cap equals the base. |
| `DEFAULT_DECAY_PER_SECOND`, `CAP_AT_BASE` | `0.0`, `NAN` | Defaults of the arguments above. |
| `base` | `var base: float` | The lowest value. Raising it lifts the value and the cap if they are below it. |
| `cap` | `var cap: float` | The highest value; finite, not below `base` (else reported and ignored). |
| `decay_per_second` | `var decay_per_second: float` | Value lost per second while slowing; finite and 0 or more. |
| `value` | `var value: float` | The value now, `base` to `cap`. Read it; change it through the methods. |
| `bump` | `bump(amount: float) -> float` | Adds `amount` up to `cap`; returns the value. Negative, NaN or INF: reported and ignored. |
| `step` | `step(delta: float, slowing: bool) -> float` | While `slowing`, subtracts `decay_per_second * delta`, never below `base`. While not, changes nothing. Returns the value. |
| `penalize` | `penalize(fraction: float) -> float` | Removes a fraction (0 to 1) of the value, never going below `base`. Outside 0 to 1 or NaN: reported and ignored. |
| `reset` | `reset() -> void` | Back to `base`. |
| `ratio` | `ratio() -> float` | 0.0 at `base` to 1.0 at `cap`; 0.0 when the cap equals the base. |
| `is_built_up` | `is_built_up() -> bool` | The value is above `base`. |

## Usage

```gdscript
# A runner: good landings build acceleration, braking wears it off, a missed jump costs a share.
extends CharacterBody2D

var acceleration := LFMomentum.new(600.0, 1800.0, 400.0)
var jumps := LFJumpPhysics.new()
var combo := LFGradeCombo.new([&"ok", &"great", &"perfect"], {&"great": 1.5, &"perfect": 2.0})
var _previous_speed := 0.0


func _physics_process(delta: float) -> void:
	var speed := velocity.length()
	# The flag is recomputed every frame: nothing latches the decay on.
	acceleration.step(delta, speed < _previous_speed)
	_previous_speed = speed


func on_landing(grade: StringName) -> void:
	combo.add(grade)
	acceleration.bump(combo.apply(50.0))            # better landings are worth more


func on_missed_jump() -> void:
	acceleration.penalize(0.2)
	combo.penalize()


func jump_velocity() -> float:
	# How built up the acceleration is feeds LFJumpPhysics' speed bonus.
	return jumps.jump_strength(400.0, 1.0, acceleration.ratio())
```

## Notes

- **Decay is on or off for each step, and you decide.** `step(delta, true)` decays; `step(delta, false)` never does. Nothing is remembered between steps, so there is no flag that can stay stuck on after the character speeds up again. The class does not decide what "slowing" means: compare speeds, check the brake, or pass `true` always for a plain fade.
- The value is always within `base` to `cap`, so a penalty or a long decay can never leave it under the base.
- `penalize` takes a fraction of the whole value, not of the part above the base. With a high base and a big fraction the result is simply the base.
- **With `LFJumpPhysics`**: `ratio()` is a ready `speed_ratio` for `jump_strength`. **With `LFGradeCombo`**: scale a bump with `combo.apply(amount)` so better results build more, and call `penalize` on both after a mistake.
- Bumps are not time-weighted; call `bump` once per event.
