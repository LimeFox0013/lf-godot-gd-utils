# LFListCursor

> A highlighted row in a list that stays inside the list, moves up and down, and says which row gets a pointer.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()`; the same maths is also available as static functions |
| **Files** | `lf_list_cursor.gd` |
| **Tests** | `tests/test_lf_list_cursor.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for a menu or list you steer with up and down keys or a d-pad: it keeps the
highlighted row valid when the list grows or shrinks and tells you where to draw the
pointer. It draws nothing, so you keep your own look. To wrap round at the ends, use
`LFUtils.cycle_index` instead.

## Step by step

1. Make a scene with one **Label** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Label

var _rows := ["Play", "Options", "Quit"]
var _cursor := LFListCursor.new(_rows.size())

func _ready() -> void:
	_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_cursor.move(1)
	elif event.is_action_pressed("ui_up"):
		_cursor.move(-1)
	_redraw()

func _redraw() -> void:
	var lines: Array[String] = []
	for i in _rows.size():
		lines.append(_cursor.marker_at(i, "> ", "  ") + _rows[i])
	text = "\n".join(lines)
```

3. Press **F6**. The pointer starts on *Play*; the down and up arrow keys move it and it stops at *Quit* and *Play*.

## API

| Member | Signature | Description |
|---|---|---|
| `index` / `count` | `var index: int` / `var count: int` | The highlighted row and the number of rows. |
| `_init` | `LFListCursor.new(rows := 0, start := 0)` | A cursor on row `start`, limited to the list. |
| `set_count` | `set_count(rows: int) -> void` | The list changed size; pulls the cursor back if it fell off the end. |
| `move` | `move(delta: int) -> bool` | Moves by `delta` rows, stopping at the ends; true if it moved. |
| `move_to` | `move_to(row: int) -> void` | Jumps to a row, limited to the list. |
| `marker_at` | `marker_at(row, shown, hidden := "") -> String` | `shown` for the cursor's row, else `hidden`. |
| `clamp_index` | `static clamp_index(position, rows) -> int` | `position` limited to `0 .. rows - 1` (0 for an empty list). |
| `step` | `static step(position, delta, rows) -> int` | `position` moved by `delta` and stopped at both ends. |
| `marker` | `static marker(row, position, shown, hidden := "") -> String` | `shown` when `row == position`, else `hidden`. |

## Usage

```gdscript
_selected = LFListCursor.step(_selected, 1, _entries.size())   # keep your own int
label.text = LFListCursor.marker(i, _selected, "> ", "  ") + names[i]
```

## Notes

- The cursor does not see your list change: call `set_count` when rows are added or removed.
- An empty list keeps the cursor on row 0, which is not a row.
