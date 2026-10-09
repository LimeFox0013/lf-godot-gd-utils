# LFControlOut

> A registry-backed `LFControl` with a `Label`, whose text can be written from anywhere by registry id.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_control_out.gd`, `lf_control_out.tscn` |
| **Tests** | `tests/test_lf_control_out.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFControl`, `LFLogger` |

## When to use it

Use it for HUD text that game code updates from far away: a score, a wave counter, a
"Gold: 120" readout. Drop `lf_control_out.tscn` into the HUD, set its `registry_id` to
`"score"`, and any script calls `LFControlOut.set_prop("score", str(score))`, with no node
path or `SceneTree` needed. It writes at most one label (the newest live holder of the id),
and warns when that control has no label. To update a label you already hold a reference
to, just set `label.text`; for many labels at once, use a group and `call_group`.

## Step by step

1. Choose *Scene → New Scene*, then click **User Interface** in the Scene dock. Save it.
2. Click the root node, then the **Instantiate Child Scene** button (the chain-link icon in
   the Scene dock) and pick `lf_control_out.tscn` from the library's folder
   (`src/components/lf_control_out/`). It comes with a Label inside, already connected.
3. Select the LFControlOut node and set *Registry Id* to `score` in the Inspector.
4. Right-click the root node, choose **Attach Script**, press *Create*, and replace the
   script's contents with:

   ```gdscript
   extends Control

   var score := 0


   func _input(event: InputEvent) -> void:   # runs for every key, click or button
   	if event is InputEventKey and event.is_pressed() and not event.is_echo():
   		score += 1   # one point per key press
   		# Write the text by id. No reference to the label is needed.
   		LFControlOut.set_prop("score", "Score: %d" % score)
   ```
5. Press **F6** (*Run Current Scene*). Press any key a few times: the text in the top-left
   corner of the window reads `Score: 1`, `Score: 2`, and so on. The same call works from
   any script anywhere in your game.

## API

Everything the class offers; you only need the rows used above to get started.

### Exports

| Member | Signature | Description |
|---|---|---|
| `label` | `@export var label: Label` | Label that receives text. The `.tscn` wires it to its child `Label`, which fills the control. |

Inherited: `registry_id` and the static helpers `by_id()`, `get_center_pos()`, `get_center_pos_on_viewport()`, `get_canvas_rect()`, `sort_reading_order()`, `place_beside()` (see `LFControl`).

### Methods

| Member | Signature | Description |
|---|---|---|
| `set_prop` | `static set_prop(prop_key: String, text: String, viewport: Viewport = null) -> void` | Finds the control with `LFControl.by_id(prop_key, viewport)`; if it is an `LFControlOut` with a `label`, sets `label.text = text`. Otherwise does nothing. |

## Usage

```gdscript
# In the HUD scene: instance lf_control_out.tscn and set its registry_id to "score"
# in the Inspector.

# score_keeper.gd, anywhere in the game (it needs no reference to the HUD):
extends Node

var score := 0


func add_points(points: int) -> void:
	score += points
	LFControlOut.set_prop("score", "Score: %d" % score)
```

## Notes

- Unknown ids and non-`LFControlOut` entries are skipped silently.
- A found `LFControlOut` whose `label` is null or freed is skipped with a `push_warning` (no script error).
- With several holders of one id, only the newest is written; when it leaves, writes reach the next-newest again (see `LFControl`).
- Despite the name, `set_prop` only writes label text; there is no generic property setter.
