# LFVirtualGrid

> A `Node2D` that tells you which rows of a long vertical list in the 2D world just came into a camera's view (`rows_entered`) and which just left it (`rows_exited`), so you build or recycle nodes for the visible rows only.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_virtual_grid.gd`, `lf_virtual_grid.tscn` |
| **Tests** | `tests/test_lf_virtual_grid.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils2D`, `LFLogger` |

## When to use it

Use it when a level or a feed is a long vertical stack of rows in the 2D world and
building every row up front is too slow: an endless tower climber built floor by floor,
a vertical shooter whose waves are rows of enemies, a leaderboard wall of 10 000 entries
the camera scrolls past. The grid tells you which row indices just came into view
(`rows_entered`) and which just left (`rows_exited`), so you build, or recycle, only the
rows on screen. A look-ahead `draw_area` builds rows before they appear, a
`viewport_tracker` keeps camera shake from churning rows, and `row_count` bounds the
list.

For lists in the UI (Controls), use Godot's built-ins instead: `ItemList` and `Tree`
already draw only their visible items, and a `ScrollContainer` is fine for short lists.
This node does not host Controls. Rows span only the vertical axis.

## Step by step

Goal: a very long list where only the rows on screen exist as nodes. Here the rows are
`Label`s and the camera scrolls down past a thousand of them.

1. *Scene → New Scene*, pick *2D Scene* (a `Node2D` root).
2. Add two children: a `Camera2D` and an `LFVirtualGrid` (search "LFVirtualGrid").
   Select the camera and set *Transform → Position* to `576, 324`, so its view starts at
   the top of row 0 (this matches the default 1152 x 648 window).
3. Select the `LFVirtualGrid` and set in the Inspector:
   - *Camera*: click *Assign…* and pick the `Camera2D`.
   - *Row Height*: `40`. The height of one row in pixels (world units).
   - *Row Count*: `1000`. Only rows 0 to 999 exist. `-1` means no limit.
4. Select the root, click *Attach Script*, *Create*, and replace the contents with:

   ```gdscript
   extends Node2D

   @onready var grid: LFVirtualGrid = $LFVirtualGrid
   @onready var camera: Camera2D = $Camera2D

   func _ready() -> void:
   	# Signals are events other code can listen to. Run our functions when they fire.
   	grid.rows_entered.connect(_on_rows_entered)
   	grid.rows_exited.connect(_on_rows_exited)

   func _process(delta: float) -> void:   # delta = seconds since the last frame
   	camera.position.y += 100.0 * delta   # scroll down, 100 pixels per second

   # Rows that just came into view: build a label for each.
   func _on_rows_entered(rows: Array[int]) -> void:
   	for row in rows:
   		var label := Label.new()
   		label.name = "Row%d" % row
   		label.text = "Row %d" % row
   		label.position = grid.get_row_rect_world(row).position   # where this row sits
   		add_child(label)

   # Rows that just left the view: remove their labels.
   func _on_rows_exited(rows: Array[int]) -> void:
   	for row in rows:
   		var label := get_node_or_null("Row%d" % row)
   		if label != null:
   			label.queue_free()
   ```
5. Save the scene and press *F6*.

You should see "Row 0" to about "Row 16" fill the window and the list scroll upward as the
camera moves down. Select the running game's *Remote* tab in the Scene dock (while the game
runs) and you will see that only about 18 `Row` labels exist at any time, not 1000. Usage below
recycles labels instead of freeing them.

## API

Everything the class offers; you only need the rows used above to get started.

### Signals

| Member | Signature | Description |
|---|---|---|
| `rows_exited` | `rows_exited(rows: Array[int])` | Row indices that are no longer visible. Within one update it is emitted **before** `rows_entered`, so their cells can be reused for the rows that enter. |
| `rows_entered` | `rows_entered(rows: Array[int])` | Row indices that just became visible. |

### Constants

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_ROW_HEIGHT` | `const float = 100.0` | Default `row_height`, in world units. |
| `DEFAULT_ROW_COUNT` | `const int = -1` | Default `row_count`: unbounded in both directions. |

### Exports

| Member | Signature | Description |
|---|---|---|
| `camera` | `Camera2D` | Camera whose viewport and canvas transform define the base view; use the viewport's current camera. Not needed when both `viewport_tracker` and `draw_area` are set. |
| `row_height` | `float = DEFAULT_ROW_HEIGHT` (100.0) | Height of one row in world units. Must be finite and `> 0`: other values are rejected with an error and the old height is kept. Changing it in the tree redraws every visible row (`refresh()`). |
| `viewport_tracker` | `Node2D` | If set, the view rect is centred on this node instead of the camera (e.g. a rig without shake). |
| `draw_area` | `Vector2 = Vector2.ZERO` | Custom view size in world units; `ZERO` means the camera's real view size. Use a larger area to draw rows ahead. |
| `row_count` | `int = DEFAULT_ROW_COUNT` (-1) | Only rows `0` to `row_count - 1` are drawn; `-1` is unbounded in both directions (negative rows included), and values below `-1` become `-1`. Changing it in the tree draws or erases just the difference. |
| `process_callback` | `Camera2D.Camera2DProcessCallback = CAMERA2D_PROCESS_IDLE` | Update on idle frames or on physics frames. Match the camera's own `process_callback`. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `base_position` | `Vector2` | World position row 0's top edge is laid out from (`base_position.y`). Captured from the node's world position in `_ready()` and by `reset()`. |
| `current_first_row` | `int = 0` | First visible row index. |
| `current_last_row` | `int = -1` | Last visible row index (`< current_first_row` means none). |

### Methods

| Member | Signature | Description |
|---|---|---|
| `reset` | `reset(new_position: Vector2 = <the node's world position>) -> void` | Sets `base_position`, moves the node to `new_position` (world space) and calls `refresh()`. |
| `refresh` | `refresh() -> void` | Erases every visible row, then draws the rows in view again (e.g. after the data behind the rows changed). |
| `clear_all` | `clear_all() -> void` | Marks no rows visible, then emits `rows_exited` for the rows that were visible (nothing when none was). The next update draws the rows in view again. |
| `get_current_visible_rows` | `get_current_visible_rows() -> Array[int]` | Indices in `[current_first_row..current_last_row]`. |
| `update_grid` | `update_grid() -> void` | Compares the rows in view with the visible ones; emits `rows_exited` for rows that left, then `rows_entered` for rows that entered. Emits nothing if unchanged. When the view is gone, erases every visible row (`clear_all`) and draws none. Runs by itself at the end of every frame; call it to update sooner. |
| `get_camera_viewport_rect_world` | `get_camera_viewport_rect_world(cam: Camera2D) -> Rect2` | The camera's view in world coordinates: the bounding box of the viewport's four corners through the canvas transform (zoom, offset, rotation). Empty when the camera is not in the tree. Same as `LFUtils2D.camera_world_rect`. |
| `get_effective_view_rect_world` | `get_effective_view_rect_world() -> Rect2` | View rect sized by `draw_area` (or the camera's view), centred on `viewport_tracker` (or the camera's view centre). Empty when the camera is needed but not in the tree. |
| `get_row_rect_world` | `get_row_rect_world(row: int) -> Rect2` | World rect of a row: view width, `row_height` tall, top at `base_position.y + row * row_height`. |
| `get_row_rect_screen` | `get_row_rect_screen(row: int) -> Rect2` | The world row rect's top-left and bottom-right corners mapped through the camera's canvas transform. Exact without camera rotation; with a rotated camera the two corners do not bound the row on screen. An empty `Rect2()` without a camera in the tree. |

## Usage

A more economical version that reuses labels. A script on a `Node2D` whose children are a `Camera2D` and an `LFVirtualGrid` (its
`camera` set to that camera in the Inspector). It shows one label per item and recycles
the labels of rows that scroll away, so only about a screenful of labels ever exists.

```gdscript
extends Node2D

@onready var grid: LFVirtualGrid = $LFVirtualGrid

var items: Array[String] = []
var cells := {}                 # row index -> the Label showing it
var spare: Array[Label] = []    # labels of rows that left, ready for reuse


func _ready() -> void:
	for i in 10000:
		items.append("Entry %d" % i)
	# Connect first: changing row_height or row_count in the tree draws right away.
	grid.rows_exited.connect(_on_rows_exited)
	grid.rows_entered.connect(_on_rows_entered)
	grid.row_height = 40.0
	grid.row_count = items.size()   # draws the rows in view


func _on_rows_exited(rows: Array[int]) -> void:
	for row in rows:
		if cells.has(row):              # rows_exited may name rows you never drew
			var label: Label = cells[row]
			label.hide()
			spare.append(label)
			cells.erase(row)


func _on_rows_entered(rows: Array[int]) -> void:
	for row in rows:
		var label: Label = spare.pop_back() if not spare.is_empty() else _make_label()
		label.global_position = grid.get_row_rect_world(row).position
		label.text = items[row]
		label.show()
		cells[row] = label


func _make_label() -> Label:
	var label := Label.new()
	add_child(label)
	return label
```

Move the camera down (`$Camera2D.position.y += 2000`) and the grid recycles the labels
that left the top for the rows that enter at the bottom.

## Notes

- The rows are drawn on the first frame update after the node is ready, so listeners connected in a parent's `_ready()` see them. `reset()`/`refresh()`, and changing `row_height` or `row_count` while in the tree, draw immediately: connect the signals before doing any of these.
- `reset()` and `refresh()` first emit `rows_exited` for the rows already visible, so a `rows_exited` listener must tolerate rows it never drew.
- A drawn row's rect overlaps the effective view; a row that only touches an edge of it is not drawn.
- Changing `row_height` redraws every visible row. Moving the node does not move the rows: `base_position` changes only through `reset()`.
- Updates run at the end of the frame, after every node (the camera included) has processed, so the drawn rows match the view that frame renders whatever the tree order. An unsmoothed camera moved during the frame is brought up to date with `force_update_scroll()` first.
- Without a view (no camera in the tree, and not both `viewport_tracker` and `draw_area`), nothing is drawn; rows appear on the first update once there is one. When the view goes away (the camera leaves the tree or is freed), the next update emits `rows_exited` for every visible row, so their nodes can be freed.
- Everything is world space: `base_position` is the grid's `global_position` (not its parent-relative `position`), so the grid may sit under any transformed parent. Outside the tree `reset()` falls back to the local `position`.
- Rows span only the vertical axis; there is no column virtualization.
- An update whose visible range is unchanged computes the view rect and the row span and emits nothing. When the range changes, the work is proportional to the rows visible before and after, not to `row_count`.
