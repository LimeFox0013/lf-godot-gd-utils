## One column of an LFTable: which key of each row it shows, and how it looks.
##
## A column has a key (`cell_name`, looked up in every row dictionary), a header title,
## width rules and an alignment. Every cell of the column, header and footer included,
## gets the same minimum width: the larger of `min_width` and its widest cell content.
## By default each cell is a text Label;
## set `build` and `update` to use any Control instead (a Button, an icon...).
class_name LFTableCellDef
extends Resource

## Upper end of the inspector slider for `min_width` and `min_height`, in pixels (larger
## values can be typed).
const _SIZE_SLIDER_MAX := 1000.0
## Inspector slider step for `min_width` and `min_height`, in pixels.
const _PIXEL_STEP := 1.0
## Property a non-LFTableCell cell shows its value through.
const _TEXT_PROPERTY := &"text"

## Column key, matched against row-dictionary keys.
@export var cell_name: String
## Header text; empty shows `cell_name`.
@export var title: String
## When `title` is empty: show `cell_name` (true) or leave the header blank (false).
@export var title_from_key := true
## Minimum column width in pixels; 0 sizes the column to its content. When above 0,
## default text cells clip (cut off) longer text instead of widening the column.
@export_range(0.0, _SIZE_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var min_width := 0.0
## Minimum cell height in pixels; 0 leaves the height to the content.
@export_range(0.0, _SIZE_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var min_height := 0.0
## When true the column takes a share of the spare width, and default text cells clip.
@export var expand := false
## Text alignment of this column's default text cells, header included.
@export var align := HORIZONTAL_ALIGNMENT_LEFT
## `func() -> Control` making an empty body cell; unset makes an LFTableCell.
var build: Callable
## `func(cell: Control, value: Variant) -> void` showing `value` in a body cell; unset
## writes the value as text (see `fill_cell`).
var update: Callable


## Creates a column showing the row key `initial_cell_name`, at least `initial_min_width`
## pixels wide, taking a share of the spare width when `initial_expand` is true.
func _init(initial_cell_name := "", initial_min_width := 0.0, initial_expand := false) -> void:
	cell_name = initial_cell_name
	min_width = initial_min_width
	expand = initial_expand


## The header text: `title`; when it is empty, `cell_name` — or nothing, with
## `title_from_key` off.
func get_title() -> String:
	if title != "" or not title_from_key:
		return title
	return cell_name


## A new empty body cell: `build`'s, or a default text cell.
func make_cell() -> Control:
	if build.is_valid():
		return build.call()
	return make_text_cell()


## A new LFTableCell for this column, aligned and clipped as the column says.
func make_text_cell() -> LFTableCell:
	var cell := LFTableCell.new()
	cell.cell_name = cell_name
	cell.horizontal_alignment = align
	cell.clip_text = min_width > 0.0 or expand
	return cell


## Shows `value` in `cell` through `update`; without one, an LFTableCell gets
## `set_cell_content(value)` and any other cell with a `text` property gets
## `str(value)` (`""` for null).
func fill_cell(cell: Control, value: Variant) -> void:
	if update.is_valid():
		update.call(cell, value)
	elif cell is LFTableCell:
		(cell as LFTableCell).set_cell_content(value)
	elif _TEXT_PROPERTY in cell:
		cell.set(_TEXT_PROPERTY, "" if value == null else str(value))
