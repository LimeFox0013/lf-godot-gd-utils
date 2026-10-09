# LFTable, LFTableCellDef, LFTableRow, LFTableCell, LFTableSection, LFTableHeader, LFTableBody, LFTableFooter

> A table with aligned columns, a header row and a footer row: describe the columns once, then hand it your rows of data.

| | |
|---|---|
| **Files** | `lf_table.gd`, `lf_table_cell_def.gd`, `lf_table_section.gd`, `lf_table_row/lf_table_row.gd`, `lf_table_cell/lf_table_cell.gd`, `lf_table_header/lf_table_header.gd`, `lf_table_body/lf_table_body.gd`, `lf_table_footer/lf_table_footer.gd` |
| **Tests** | `tests/test_lf_table.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFTable` | Node: add it to a scene |
| `LFTableCellDef` | Resource: create it in the FileSystem dock, or with `.new()` |
| `LFTableCell` | Part of `LFTable`, created for you |
| `LFTableRow` | Part of `LFTable`, created for you |
| `LFTableSection` | Part of `LFTable`, created for you |
| `LFTableHeader` | Part of `LFTable`, created for you |
| `LFTableBody` | Part of `LFTable`, created for you |
| `LFTableFooter` | Part of `LFTable`, created for you |

## When to use it

Use it for any screen that lists data in columns: a scoreboard, an inventory list, a
shop with a "Buy" button per row, a stats sheet with a totals row. You describe the
columns once and hand it plain dictionaries. Refilling it every frame with unchanged
data costs one deep `==` per row and touches no node; when anything changed, each row that
differs from the one shown at its position is copied and compared cell by cell, only the
cells whose value changed are refilled, and the column widths are re-measured once, at the
end of the frame. `set_strip`
covers one row of N identical cards (shop slots, party portraits). Godot's
`GridContainer` aligns columns but has no rows to index, no header and no data binding;
for thousands of plain-text rows prefer Godot's `Tree` or `ItemList`, which keep no
Control per cell but cannot hold arbitrary Controls (buttons, pickers) in their cells.

## Step by step

1. *Scene → New Scene*, then click **User Interface** (a `Control` root). Rename it `Scoreboard` and save (*Ctrl+S*, or *Cmd+S* on macOS) as `table_demo.tscn`.
2. Click **+ Add Child Node**, type `LFTable` in the search box, and create it. Leave **Header** on (the first row shows column titles); **Footer** is off.
3. Right-click `Scoreboard`, choose **Attach Script**, click *Create*, and use this code. A *Dictionary* is a set of named values written `{"key": value}`: each row of the table is one dictionary, and each column shows one key.

```gdscript
extends Control

@onready var table: LFTable = $LFTable

var scores: Array[Dictionary] = [
	{"name": "Fox", "score": 120},
	{"name": "Owl", "score": 95},
	{"name": "Hare", "score": 40},
]


func _ready() -> void:
	# One LFTableCellDef per column: the key to show, and a minimum width in pixels.
	var name_column := LFTableCellDef.new("name", 140.0)
	name_column.title = "Player"
	var score_column := LFTableCellDef.new("score", 80.0)
	score_column.title = "Score"
	score_column.align = HORIZONTAL_ALIGNMENT_RIGHT
	table.cell_defs = [name_column, score_column]
	table.set_table_data(scores)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):  # Enter or Space
		scores[0]["score"] += 10  # Fox scores 10 points
		table.set_table_data(scores)  # only the changed cell is refilled
```

4. Press **F6** (*Run Current Scene*). You should see a header row `Player | Score` and three rows: Fox 120, Owl 95, Hare 40, with the scores right-aligned. Press **Enter** (or Space): Fox's score becomes 130, then 140...
5. Make it yours: change the keys (`"name"`, `"score"`) to your own, add more `LFTableCellDef` columns (the second number is the minimum column width in pixels; a third value `true` lets a column take the spare width), and fill `scores` with your own data. For a button in every row, see the first example under **Usage**.

## API

Everything the class offers; you only need the rows used above to get started.

### LFTable — Exports / Properties

| Member | Signature | Description |
|---|---|---|
| `header` | `@export var header := true` | Build a header section showing each column's title. Read once, at `_ready()`. |
| `footer` | `@export var footer := false` | Build a footer section showing `footer_data`; hidden while `footer_data` is empty. Read once, at `_ready()`. |
| `cell_defs` | `@export var cell_defs: Array[LFTableCellDef] = []` | Columns, in display order. Setting it refills the header, every row and the footer; a row's cells are made anew only when the list holds other def objects (or another count) than before. A def changed in place shows its new `title`, `min_width` and `min_height` once the list is set again, but its `align`, `expand`, `build` and text clipping reach only cells made later: set new `LFTableCellDef` objects to apply those. |
| `rows_data` | `@export var rows_data: Array[Dictionary] = []` | The rows shown, as deep copies of what was passed in. Reading it returns a fresh deep copy (edit it, then pass it back to `set_table_data`); setting it is `set_table_data`. |
| `footer_data` | `@export var footer_data: Dictionary = {}` | The footer row's data (e.g. totals), keyed like a body row. The footer hides while it is empty. |
| `DEFAULT_COLUMN_SEPARATION` | `const DEFAULT_COLUMN_SEPARATION := -1` | Default `column_separation`: keep the theme's. |
| `DEFAULT_ROW_SEPARATION` | `const DEFAULT_ROW_SEPARATION := -1` | Default `row_separation`: keep the theme's. |
| `column_separation` | `@export var column_separation := DEFAULT_COLUMN_SEPARATION` (-1) | Pixels between columns in every row (header and footer included); `-1` keeps the theme's. |
| `row_separation` | `@export var row_separation := DEFAULT_ROW_SEPARATION` (-1) | Pixels between body rows; `-1` keeps the theme's. |
| `header_section` | `var header_section: LFTableHeader` | Header section, or null when `header` is off (an `LFTableHeader` already among the children is adopted either way). |
| `body` | `var body: LFTableBody` | Body section; set once the table is ready. |
| `footer_section` | `var footer_section: LFTableFooter` | Footer section, or null when `footer` is off (an `LFTableFooter` already among the children is adopted either way). |

### LFTable — Methods

| Member | Signature | Description |
|---|---|---|
| `set_table_data` | `set_table_data(rows: Array) -> void` | Shows `rows`. Non-Dictionary entries are skipped with a warning. Data equal to what is shown is compared (one deep `==` per row), not copied, and changes nothing; otherwise each row that differs from the one shown at its position is copied, existing rows are refilled in place (only cells whose value changed are touched), the pool grows or shrinks, and the columns are re-measured at the end of the frame. `rows_data` can be passed back as it is. |
| `add_row` | `add_row(row_data: Dictionary) -> void` | Appends a row (a copy of `row_data`); the columns are re-measured at the end of the frame. |
| `set_row` | `set_row(index: int, row_data: Dictionary) -> void` | Replaces row `index` in place (only cells whose value changed are touched; the columns are re-measured at the end of the frame). Data equal to the shown row is compared (one deep `==`) and changes nothing. Out of range: warning, no change. |
| `remove_row` | `remove_row(index: int) -> void` | Removes row `index` at once; later rows move up. Out of range: warning, no change. |
| `clear_rows` | `clear_rows() -> void` | Removes every row at once. |
| `row_count` | `row_count() -> int` | Number of rows (`rows_data.size()`). |
| `get_row` | `get_row(index: int) -> LFTableRow` | Row `index`, or null (out of range, or before ready). |
| `get_cell` | `get_cell(row: int, column: int) -> Control` | Cell of column `column` in row `row`, or null. |
| `column_index` | `column_index(cell_name: String) -> int` | Index of the column with that `cell_name`, or `-1`. |
| `set_strip` | `set_strip(items: Array, template: LFTableCellDef) -> void` | A null `template` logs an error and changes nothing. Shows `items` as one row of identical cells: one column per item, each a copy of `template` (widths, height, align, expand, `build`, `update`) keyed `"0"`, `"1"`… Columns are re-made only when the count or the template changes (or `cell_defs` was set by hand since); otherwise cells are refilled in place and an unchanged item touches nothing. No items, no row. Replaces earlier columns. |
| `strip_size` | `strip_size() -> int` | Number of cells `set_strip` last laid out; `0` once `cell_defs` is set to other columns. |
| `strip_cell` | `strip_cell(index: int) -> Control` | Strip cell `index`, or null (out of range, or before ready). |
| `render_header` | `render_header() -> void` | Refills the header row from the column titles (e.g. after changing a `title` in place). Called by `_ready()` and the `cell_defs` setter. No-op without a header section. |

Before `_ready()` the row methods only record into `rows_data`; `_ready()` builds the sections (adopting `LFTableHeader`/`LFTableBody`/`LFTableFooter` children already there) and shows everything.

### LFTableCellDef (Resource)

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFTableCellDef.new(initial_cell_name := "", initial_min_width := 0.0, initial_expand := false)` | A column showing row key `initial_cell_name`, at least `initial_min_width` px wide, taking spare width when `initial_expand` is true. |
| `cell_name` | `@export var cell_name: String` | Row-dictionary key the column shows. |
| `title` | `@export var title: String` | Header text; empty shows `cell_name` (see `title_from_key`). |
| `title_from_key` | `@export var title_from_key := true` | With an empty `title`: `true` shows `cell_name`, `false` leaves the header cell blank. |
| `min_width` | `@export var min_width := 0.0` | Minimum column width in px. Every cell of the column gets the larger of this and the widest cell content as its minimum width (an `expand` column can grow past it). Above 0, default text cells clip instead of widening the column. |
| `min_height` | `@export var min_height := 0.0` | Minimum height (px) of every cell in the column. |
| `expand` | `@export var expand := false` | The column takes a share of the spare row width; default text cells clip. |
| `align` | `@export var align := HORIZONTAL_ALIGNMENT_LEFT` | Alignment of the column's default text cells, header included. |
| `build` | `var build: Callable` | `func() -> Control` making an empty body cell. Unset: an `LFTableCell`. |
| `update` | `var update: Callable` | `func(cell: Control, value: Variant) -> void` showing a value in a body cell. Unset: see `fill_cell`. |
| `get_title` | `get_title() -> String` | `title`; when empty, `cell_name`, or `''` with `title_from_key` off. |
| `make_cell` | `make_cell() -> Control` | A new body cell: `build`'s, or `make_text_cell()`. |
| `make_text_cell` | `make_text_cell() -> LFTableCell` | A default text cell, aligned and clipped as the column says. |
| `fill_cell` | `fill_cell(cell: Control, value: Variant) -> void` | Calls `update`; without one, `LFTableCell.set_cell_content(value)`, or sets any other cell's `text` property to `str(value)` (`""` for null). |

### LFTableRow (HBoxContainer)

| Member | Signature | Description |
|---|---|---|
| `cell_minimum_size_changed` | `signal cell_minimum_size_changed` | A cell's minimum size changed on its own (the table re-aligns its columns at the end of the frame, deferred). |
| `row_data` | `var row_data: Dictionary` | The data the row last showed, as a fresh deep copy each read (editing it changes nothing). |
| `set_row_data` | `set_row_data(data: Dictionary, cell_defs: Array[LFTableCellDef], text_only := false) -> void` | Rebuilds the cells when the defs differ from last time; otherwise refills only the cells whose value changed (a value of a different type counts as changed). A missing key is null. `text_only` makes every cell a default text cell (header and footer rows). Keeps a deep copy of `data`. |
| `get_cell` | `get_cell(column: int) -> Control` | Cell `column`, or null. |

### LFTableCell (Label)

| Member | Signature | Description |
|---|---|---|
| `cell_name` | `@export var cell_name: String` | Column this cell belongs to. |
| `set_cell_content` | `set_cell_content(content: Variant) -> void` | `text = str(content)`, `""` for null. No word wrap; a line break in the value still starts a new line. |

`LFTableSection`, `LFTableHeader`, `LFTableBody`, `LFTableFooter` have no members; the table finds them by class, so a scene can place (and style) its own.

### Shape (for indexing)

- `body.get_child(i)` is row `i` (`get_row(i)`), an `LFTableRow`.
- `row.get_child(j)` is the cell of `cell_defs[j]` (`get_cell(i, j)`).
- `header_section.get_child(0)` / `footer_section.get_child(0)` are the header and footer rows, same cell order.
- Sections are ordered header, body, footer.

## Usage

```gdscript
# scoreboard.gd: attach to a Control node in your scene.
extends Control

var table := LFTable.new()


func _ready() -> void:
	# Columns: a stretching name column, a right-aligned kills column, and a button column.
	var player := LFTableCellDef.new("name", 0.0, true)  # key, min width, expand
	player.title = "Player"
	var kills := LFTableCellDef.new("kills")
	kills.title = "Kills"
	kills.align = HORIZONTAL_ALIGNMENT_RIGHT
	var kick := LFTableCellDef.new("kick", 80.0)
	kick.title = ""
	kick.title_from_key = false  # blank header for the button column
	kick.build = func() -> Control: return Button.new()
	kick.update = func(cell: Control, value: Variant) -> void: (cell as Button).text = str(value)

	table.cell_defs = [player, kills, kick]
	table.footer = true  # read once, when the table enters the tree
	table.column_separation = 12
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table)

	# One dictionary per row, keyed by column. A missing key shows an empty cell.
	table.set_table_data([
		{"name": "Fox", "kills": 12, "kick": "Kick"},
		{"name": "Owl", "kick": "Kick"},
	])
	table.footer_data = {"name": "Total", "kills": 12}

	# Fixed shape: row 0, column 2 is Fox's button.
	var fox_kick := table.get_cell(0, 2) as Button
	fox_kick.pressed.connect(func() -> void: print("kick Fox"))


func _process(_delta: float) -> void:
	# Unchanged data is only compared (one deep == per row). A changed value refills only
	# its own cell, and the columns are re-measured once at the end of the frame, however
	# many rows changed.
	table.set_row(1, {"name": "Owl", "kills": 3, "kick": "Kick"})
```

A row of identical cards (shop slots, party portraits), refilled in place:

```gdscript
# shop_bar.gd: attach to a Control node.
extends Control

var shop := LFTable.new()
var card := LFTableCellDef.new("card", 160.0)  # keep ONE template and reuse it


func _ready() -> void:
	shop.header = false  # a strip has no header
	add_child(shop)
	card.build = func() -> Control: return Button.new()
	card.update = func(cell: Control, slot: Variant) -> void: (cell as Button).text = str(slot) if slot else "Empty"
	show_slots(["Sword", "Shield", null])


func show_slots(slots: Array) -> void:
	shop.set_strip(slots, card)  # same count as last time: cards refilled in place
	var first_card := shop.strip_cell(0) as Button
	print(first_card.text, " / ", shop.strip_size(), " cards")
```

## Notes

- The table owns every cell's `custom_minimum_size` (it writes the column width and `min_height` there); size a column through `min_width`/`min_height`, not on the cell.
- Columns stay aligned when a cell's content changes by itself (e.g. a button's text set from outside); the table re-aligns at the end of the frame (deferred).
- Row changes (`set_table_data`, `set_row`, `add_row`, `remove_row`), `cell_defs` and `footer_data` re-measure the columns once at the end of the frame, however many were made, so a cell's `custom_minimum_size` reflects them from the next frame on (the first layout, when the table becomes ready, is measured at once). One measure walks every cell of every row.
- A builder's cell is reused for whatever row lands in its slot. Connect its signals once in `build`, and read the row it belongs to when the signal fires (e.g. from metadata set in `update`) rather than capturing row data.
- Rows that drop out are removed from the table immediately and deleted at the end of the frame, so counting the rows' nodes right after a call is correct.
- A strip's columns are rebuilt (and its cells freed) only when the item count or the template object changes; keep one template instance and pass it every time. A strip with `header` on shows a header row of `0`, `1`… (or the template's title); turn it off.
- `rows_data` holds deep copies, and reading it gives another copy: changing a dictionary you passed in or read back changes nothing until it is passed again. For a big table read every frame, keep your own rows and call `set_row` / `set_table_data` instead of reading `rows_data`.
