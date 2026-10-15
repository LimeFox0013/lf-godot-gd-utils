# LFMilestones

> Reports each multiple of a step the first time a value reaches it.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_milestones.gd` |
| **Tests** | `tests/test_lf_milestones.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to announce round numbers during a climb or a run, such as every 50 m, with a bigger mark every fifth one. Falling back and rising again does not repeat a milestone.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*.
3. Replace everything in the script with the code below (the `#` text is a note that Godot ignores):

   ```gdscript
   extends Node

   var marks := LFMilestones.new(50.0, 5)


   func _ready() -> void:
   	for h in [30.0, 120.0, 60.0, 130.0, 260.0]:
   		for m in marks.advance(h):
   			print(m.value, " big" if m.big else "")
   ```
4. Press **F6** (*Run Current Scene*) and save the scene when asked, for example as `test.tscn`.
5. In the *Output* panel you should see `50.0`, `100.0`, then `150.0`, `200.0`, `250.0 big` (the 60 and 130 steps report nothing new).

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_STEP`, `DEFAULT_BIG_EVERY` | `10.0`, `5` | Defaults of the arguments below. |
| `new` | `LFMilestones.new(step_size := DEFAULT_STEP, big_every := DEFAULT_BIG_EVERY)` | A step of 0 or less, NaN or infinite, or `big_every` below 1, is reported through `LFLogger` and the default is used. |
| `advance` | `advance(value: float) -> Array[Dictionary]` | Milestones first reached by `value`, oldest first, each `{value, number, big}`. A NaN or infinite value is reported and returns nothing. |
| `reset` | `reset() -> void` | Forgets every milestone reported. |
| `step` | `var step: float` | Distance between milestones. Read only. |
| `reached` | `var reached: int` | Highest milestone number reported so far. Read only. |

## Notes

- Milestones start at `step`; a value of 0 or below reports nothing.
- One call can return several milestones when the value jumps.
