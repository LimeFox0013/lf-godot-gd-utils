## A table that shows rows of data in aligned columns, with an optional header and footer.
##
## Describe the columns once (`cell_defs`, one LFTableCellDef each), then pass the rows as
## dictionaries keyed by column (`set_table_data`). An optional header row shows the
## column titles and an optional footer row shows `footer_data` (e.g. totals). Every
## cell of a column gets the same minimum width, the larger of its `min_width` and its
## widest cell content, so the columns line up (an `expand` column also takes spare
## width). Cells are text by default; a column's `build`/`update`
## callables make them any Control (a Button, an icon...).
##
## The shape is fixed, so code can index into it: row i is body child i, and cell j of a
## row is row child j, in `cell_defs` order. Rows are pooled (kept and reused): new data
## refills the existing rows in place, rows are only added or freed when the count
## changes, and only the cells whose value changed are refilled. Passing data equal to
## what is shown only compares it with the shown rows (one `==` per row, no copy) and
## changes nothing; otherwise each row that differs from the one shown at its position is
## copied and compared cell by cell. Column widths are re-measured once at the end of the
## frame after any change (deferred), not per call.
## Before the table is ready (in the tree), row changes are only recorded in `rows_data`
## and shown once it is.
class_name LFTable
extends VBoxContainer

static var _log := LFLogger.new()

## Default `column_separation`: -1 keeps the theme's HBoxContainer separation.
const DEFAULT_COLUMN_SEPARATION := -1
## Default `row_separation`: -1 keeps the theme's VBoxContainer separation.
const DEFAULT_ROW_SEPARATION := -1
## Upper end of the inspector slider for the separations, in pixels (larger values can be
## typed).
const _SEPARATION_SLIDER_MAX := 100
## Inspector slider step for the separations, in pixels.
const _PIXEL_STEP := 1
## Theme constant name of a box container's spacing.
const _SEPARATION := &"separation"

## Builds a header section showing each column's title. Read once, when the table
## becomes ready.
@export var header := true
## Builds a footer section showing `footer_data`; hidden while `footer_data` is empty.
## Read once, when the table becomes ready.
@export var footer := false
## Column definitions, in display order. Setting it refills the header, every row and
## the footer; a row's cells are made anew only when the list holds other def objects
## (or another count) than that row last used. So a def changed in place shows its new
## `title`, `min_width` and `min_height` once the list is set again (or `render_header`
## runs, for a title), but its `align`, `expand`, `build` and text clipping reach only
## cells made later: set new LFTableCellDef objects to apply those.
@export var cell_defs: Array[LFTableCellDef] = []:
	set(value):
		cell_defs = value
		if body:
			render_header()
			_render_all_rows()
			_render_footer()
			_queue_sync()
## The rows shown, as copies of the dictionaries passed in. Reading it returns a fresh
## deep copy, so editing what you read changes nothing until you pass it back. Setting it
## is `set_table_data`.
@export var rows_data: Array[Dictionary] = []:
	get:
		return _rows.duplicate(true)
	set(value):
		set_table_data(value)
## Data of the footer row, keyed like a body row. Shown by the footer section (made when
## `footer` is on, or placed by the scene), which hides while this is empty.
@export var footer_data: Dictionary = {}:
	set(value):
		footer_data = value.duplicate(true)
		if body:
			_render_footer()
			_queue_sync()
## Pixels between columns in every row; -1 keeps the theme's HBoxContainer separation.
@export_range(-1, _SEPARATION_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var column_separation := DEFAULT_COLUMN_SEPARATION:
	set(value):
		column_separation = value
		if body:
			_apply_separations()
## Pixels between body rows; -1 keeps the theme's VBoxContainer separation.
@export_range(-1, _SEPARATION_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var row_separation := DEFAULT_ROW_SEPARATION:
	set(value):
		row_separation = value
		if body:
			_apply_separations()

## Header section, or null when `header` is off and the scene placed none.
var header_section: LFTableHeader
## Body section holding one LFTableRow per row; set once the table is ready.
var body: LFTableBody
## Footer section, or null when `footer` is off and the scene placed none.
var footer_section: LFTableFooter

var _rows: Array[Dictionary] = []
var _sync_queued := false
var _strip_template: LFTableCellDef = null
var _strip_columns: Array[LFTableCellDef] = []


func _ready() -> void:
	_build_sections()
	render_header()
	_render_all_rows()
	_render_footer()
	_sync_columns()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_queue_sync()


## Rebuilds the header row: one text cell per column showing its title. A no-op
## without a header section.
func render_header() -> void:
	if not header_section:
		return
	var titles := {}
	for cell_def in cell_defs:
		titles[cell_def.cell_name] = cell_def.get_title()
	var row := _header_row()
	row._show_owned(titles, cell_defs, true)
	# Columns sharing a key share one entry in `titles`; each cell takes its own title.
	for column in cell_defs.size():
		(row.get_cell(column) as LFTableCell).set_cell_content(cell_defs[column].get_title())


## Shows `rows` (Dictionaries; anything else is skipped with a warning). Existing rows
## are refilled in place and the pool grows or shrinks to fit; data equal to what is
## shown is only compared, not copied, and changes nothing.
func set_table_data(rows: Array) -> void:
	if _is_shown(rows):
		return
	var new_rows: Array[Dictionary] = []
	for row: Variant in rows:
		if row is Dictionary:
			# A row equal to the one shown at its slot keeps the copy already held.
			var slot := new_rows.size()
			if slot < _rows.size() and row == _rows[slot]:
				new_rows.append(_rows[slot])
			else:
				new_rows.append((row as Dictionary).duplicate(true))
		else:
			_log.warning("LFTable: skipping a row that is not a Dictionary: %s" % [row])
	if new_rows == _rows:
		return
	_rows = new_rows
	if not body:
		return
	_render_all_rows()
	_queue_sync()


## Appends a row at the bottom. The dictionary is copied, so changing it afterwards
## changes nothing on screen.
func add_row(row_data: Dictionary) -> void:
	_rows.append(row_data.duplicate(true))
	if not body:
		return
	_render_row(_rows.size() - 1)
	_queue_sync()


## Replaces row `index` in place. Data equal to the shown row is only compared (one `==`)
## and changes nothing. An index out of range warns and changes nothing.
func set_row(index: int, row_data: Dictionary) -> void:
	if not _check_index(index):
		return
	if row_data == _rows[index]:
		return
	_rows[index] = row_data.duplicate(true)
	if not body:
		return
	_render_row(index)
	_queue_sync()


## Removes row `index`; the rows after it move up one. An index out of range warns
## and changes nothing.
func remove_row(index: int) -> void:
	if not _check_index(index):
		return
	_rows.remove_at(index)
	if not body:
		return
	var row := body.get_child(index)
	body.remove_child(row)
	row.queue_free()
	_queue_sync()


## Removes every row; the body's child count drops at once.
func clear_rows() -> void:
	set_table_data([])


## Number of rows (body rows only; the header and footer are not counted).
func row_count() -> int:
	return _rows.size()


## Row `index`, or null when out of range or before the table is ready.
func get_row(index: int) -> LFTableRow:
	if not body or index < 0 or index >= body.get_child_count():
		return null
	return body.get_child(index)


## The cell of column `column` in row `row`, or null when either is out of range.
func get_cell(row: int, column: int) -> Control:
	var table_row := get_row(row)
	return table_row.get_cell(column) if table_row else null


## Lays `items` out as one row of identical cells: one column per item, each a copy of
## `template` (widths, height, alignment, expand, `build`, `update`) keyed "0", "1"...
## Columns are re-made only when the count or the template changes; otherwise each
## cell is refilled in place and an unchanged item touches nothing, so a strip refilled
## every frame with the same count and template frees no cell (a Button mid-click). No
## items, no row. Replaces any
## columns set before; turn `header` off for a strip.
func set_strip(items: Array, template: LFTableCellDef) -> void:
	if template == null:
		_log.error("LFTable.set_strip needs a template column")
		return
	if _strip_template != template or strip_size() != items.size() or (items.is_empty() and not cell_defs.is_empty()):
		# Emptied first, so no cell is ever filled for a column its data lacks.
		set_table_data([])
		var columns: Array[LFTableCellDef] = []
		for i in items.size():
			columns.append(_strip_column(template, i))
		_strip_template = template
		_strip_columns = columns
		cell_defs = columns
	var row := {}
	for i in items.size():
		row[str(i)] = items[i]
	set_table_data([row] if not items.is_empty() else [])


## Number of cells in the strip `set_strip` last laid out; 0 once `cell_defs` is set
## to other columns.
func strip_size() -> int:
	return _strip_columns.size() if cell_defs == _strip_columns else 0


## Cell `index` of the strip, or null when out of range or before the table is ready.
func strip_cell(index: int) -> Control:
	if index < 0 or index >= strip_size():
		return null
	return get_cell(0, index)


## Index of the column whose `cell_name` is `cell_name`, or -1 when no column has it.
func column_index(cell_name: String) -> int:
	for column in cell_defs.size():
		if cell_defs[column].cell_name == cell_name:
			return column
	return -1


static func _strip_column(template: LFTableCellDef, index: int) -> LFTableCellDef:
	var column := LFTableCellDef.new(str(index), template.min_width, template.expand)
	column.title = template.title
	column.title_from_key = template.title_from_key
	column.min_height = template.min_height
	column.align = template.align
	column.build = template.build
	column.update = template.update
	return column


## Whether `rows` holds exactly the shown rows (all Dictionaries, equal in order).
func _is_shown(rows: Array) -> bool:
	if rows.size() != _rows.size():
		return false
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or row != _rows[index]:
			return false
	return true


func _check_index(index: int) -> bool:
	if index >= 0 and index < _rows.size():
		return true
	_log.warning("LFTable: row index %d out of range (%d rows)" % [index, _rows.size()])
	return false


## Adopts header/body/footer sections already among the children, makes the missing
## ones, and orders them header, body, footer.
func _build_sections() -> void:
	for child in get_children():
		if child is LFTableHeader:
			header_section = child
		elif child is LFTableBody:
			body = child
		elif child is LFTableFooter:
			footer_section = child

	if not body:
		body = LFTableBody.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(body)
	if header and not header_section:
		header_section = LFTableHeader.new()
		add_child(header_section)
	if footer and not footer_section:
		footer_section = LFTableFooter.new()
		add_child(footer_section)

	if header_section:
		move_child(header_section, body.get_index())
	if footer_section:
		move_child(footer_section, body.get_index() + 1)
	_apply_separations()


func _header_row() -> LFTableRow:
	if header_section.get_child_count() == 0:
		header_section.add_child(_new_row())
	return header_section.get_child(0)


func _render_footer() -> void:
	if not footer_section:
		return
	if footer_section.get_child_count() == 0:
		footer_section.add_child(_new_row())
	footer_section.visible = not footer_data.is_empty()
	(footer_section.get_child(0) as LFTableRow).set_row_data(footer_data, cell_defs, true)


## Grows or shrinks the row pool to `_rows` and refills every row.
func _render_all_rows() -> void:
	while body.get_child_count() > _rows.size():
		var extra := body.get_child(body.get_child_count() - 1)
		body.remove_child(extra)
		extra.queue_free()
	for index in _rows.size():
		_render_row(index)


func _render_row(index: int) -> void:
	if index >= body.get_child_count():
		body.add_child(_new_row())
	# The row keeps the table's own copy: `_rows` entries are replaced, never edited.
	(body.get_child(index) as LFTableRow)._show_owned(_rows[index], cell_defs)


func _new_row() -> LFTableRow:
	var row := LFTableRow.new()
	if column_separation >= 0:
		row.add_theme_constant_override(_SEPARATION, column_separation)
	row.cell_minimum_size_changed.connect(_queue_sync)
	return row


func _apply_separations() -> void:
	var rows: Array[Node] = body.get_children()
	if header_section:
		rows.append_array(header_section.get_children())
	if footer_section:
		rows.append_array(footer_section.get_children())
	for row in rows:
		if column_separation >= 0:
			(row as Control).add_theme_constant_override(_SEPARATION, column_separation)
		else:
			(row as Control).remove_theme_constant_override(_SEPARATION)
	if row_separation >= 0:
		body.add_theme_constant_override(_SEPARATION, row_separation)
	else:
		body.remove_theme_constant_override(_SEPARATION)


func _queue_sync() -> void:
	if _sync_queued:
		return
	_sync_queued = true
	_sync_columns.call_deferred()


## Gives every cell of a column the same minimum width: the larger of the column's
## `min_width` and its widest cell content, header and footer included.
func _sync_columns() -> void:
	_sync_queued = false
	if not body:
		return
	var rows: Array[LFTableRow] = []
	if header_section and header_section.get_child_count() > 0:
		rows.append(header_section.get_child(0))
	for row in body.get_children():
		rows.append(row)
	if footer_section and footer_section.visible and footer_section.get_child_count() > 0:
		rows.append(footer_section.get_child(0))
	for column in cell_defs.size():
		var cell_def := cell_defs[column]
		var width := cell_def.min_width
		for row in rows:
			var cell := row.get_cell(column)
			if cell:
				width = maxf(width, cell.get_minimum_size().x)
		var minimum := Vector2(width, cell_def.min_height)
		for row in rows:
			var cell := row.get_cell(column)
			if cell:
				cell.custom_minimum_size = minimum
