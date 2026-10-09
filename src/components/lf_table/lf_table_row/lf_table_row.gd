## One row of an LFTable: one cell per column, child j being the cell of column j. Cells
## are made again only when the column defs change; otherwise they are refilled in place,
## and only the cells whose value changed are touched.
class_name LFTableRow
extends HBoxContainer

## Emitted when one of the row's cells changes its minimum size on its own.
signal cell_minimum_size_changed

## The data the row last showed: a fresh deep copy each read, so editing it changes
## nothing. Setting it changes only what the next `set_row_data` compares against.
var row_data: Dictionary:
	get:
		return _row_data.duplicate(true)
	set(value):
		_row_data = value.duplicate(true)

var _row_data: Dictionary = {}
var _cell_defs: Array[LFTableCellDef] = []
var _text_only := false


## Shows `data`, one cell per def; a missing key shows as null (an empty text cell).
## The cells are rebuilt when the defs differ from the last call, otherwise only the
## cells whose value changed are refilled. With `text_only`, every cell is a default
## text cell showing the value as text (used for header and footer rows). The row keeps a
## deep copy of `data`.
func set_row_data(data: Dictionary, cell_defs: Array[LFTableCellDef], text_only := false) -> void:
	_show(data, cell_defs, text_only)
	_row_data = data.duplicate(true)


## `set_row_data` keeping `data` itself instead of a copy — for a caller that already
## holds a private copy it never edits in place (LFTable's own rows).
func _show_owned(data: Dictionary, cell_defs: Array[LFTableCellDef], text_only := false) -> void:
	_show(data, cell_defs, text_only)
	_row_data = data


func _show(data: Dictionary, cell_defs: Array[LFTableCellDef], text_only: bool) -> void:
	var rebuilt := cell_defs != _cell_defs or text_only != _text_only or get_child_count() != cell_defs.size()
	if not rebuilt and is_same(data, _row_data):
		return # the very dictionary shown last, never edited in place by `_show_owned` callers
	if rebuilt:
		_build_cells(cell_defs, text_only)
	for column in cell_defs.size():
		var key := cell_defs[column].cell_name
		var value: Variant = data.get(key)
		if rebuilt or not _same(value, _row_data.get(key)) or data.has(key) != _row_data.has(key):
			_fill(column, value)


## The cell of column `column`, or null when out of range.
func get_cell(column: int) -> Control:
	if column < 0 or column >= get_child_count():
		return null
	return get_child(column)


func _build_cells(cell_defs: Array[LFTableCellDef], text_only: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cell_defs = cell_defs.duplicate()
	_text_only = text_only
	for cell_def in cell_defs:
		var cell: Control = cell_def.make_text_cell() if text_only else cell_def.make_cell()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if cell_def.expand else Control.SIZE_FILL
		cell.minimum_size_changed.connect(_on_cell_minimum_size_changed)
		add_child(cell)


func _fill(column: int, value: Variant) -> void:
	var cell_def := _cell_defs[column]
	var cell: Control = get_child(column)
	if _text_only:
		(cell as LFTableCell).set_cell_content(value)
	else:
		cell_def.fill_cell(cell, value)


func _on_cell_minimum_size_changed() -> void:
	cell_minimum_size_changed.emit()


static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
