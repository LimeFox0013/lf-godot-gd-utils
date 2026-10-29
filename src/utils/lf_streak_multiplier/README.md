# LFStreakMultiplier

> A multiplier that grows by a fixed step with every good result in a row, and drops back when the streak breaks.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_streak_multiplier.gd` |
| **Tests** | `tests/test_lf_streak_multiplier.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it for a score or reward multiplier that rises with each consecutive success, such as
x1.0, x1.2, x1.4 for every platform a player lands on, and goes back to x1.0 on a miss. It has
no grades and no penalty rule: for graded results use `LFGradeCombo`, for a value that fades
over time use `LFMomentum`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*.
3. Replace everything in the script with the code below (the `#` text is a note that Godot ignores):

   ```gdscript
   extends Node

   # Starts at x1, grows 0.5 per good landing, stops at x3.
   var bonus := LFStreakMultiplier.new(1.0, 0.5, 3.0)


   func _ready() -> void:
   	print(bonus.hit())   # 1.5
   	print(bonus.hit())   # 2.0
   	bonus.reset()        # the player fell
   	print(bonus.value)   # 1.0
   ```
4. Press **F6** (*Run Current Scene*) and save the scene when asked, for example as `test.tscn`.
5. In the *Output* panel you should see `1.5`, `2.0` and `1.0`.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_BASE`, `DEFAULT_STEP`, `DEFAULT_CEILING` | `1.0`, `0.2`, `5.0` | Defaults of the arguments below. |
| `new` | `LFStreakMultiplier.new(base := DEFAULT_BASE, step := DEFAULT_STEP, ceiling := DEFAULT_CEILING)` | A step of 0 or less, a ceiling below `base`, or a NaN or infinite argument is reported through `LFLogger` and the default is used. |
| `hit` | `hit() -> float` | Counts a hit, raises the value by one step up to the ceiling, returns it. |
| `reset` | `reset() -> void` | Value back to `base`, count to 0. |
| `value` | `var value: float` | The value now. Read only. |
| `count` | `var count: int` | Hits since the last `reset`, hits at the ceiling included. Read only. |
| `changed` | `signal changed(value: float)` | After a `hit` or `reset` that changed the value. |

## Usage

```gdscript
var score_mult := LFStreakMultiplier.new()   # x1.0, +0.2 per hit, at most x5.0
score_mult.changed.connect(_on_mult_changed) # a method, not a lambda

func _on_landed(good: bool) -> void:
	if good:
		score += int(100 * score_mult.hit())
	else:
		score_mult.reset()

func _on_mult_changed(value: float) -> void:
	label.text = "x%.1f" % value
```

## Notes

- The value is `minf(base + step * count, ceiling)`, so it does not drift over many hits.
- A hit at the ceiling is counted but does not emit `changed`; a `reset` at the base emits nothing.
- A ceiling below `base` falls back to the default ceiling, or to `base` if that is higher.
