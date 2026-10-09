## A scrolling list of text lines, such as an activity log or a debug console.
##
## `append` adds a line at the bottom, the oldest lines are dropped past `max_lines`, and
## while `follow` is on the view scrolls to the bottom whenever its scroll range changes. Each line is a Label;
## line i is child i of `lines`, oldest first.
class_name LFLogView
extends ScrollContainer

## Default `max_lines`: the most lines kept.
const DEFAULT_MAX_LINES := 100

## Node name of the `lines` box.
const _LINES_NAME := 'Lines'
## Theme colour a line's Label draws its text in.
const _FONT_COLOR := &"font_color"
## Theme font size of a line's Label.
const _FONT_SIZE := &"font_size"

## Most lines kept; appending past it drops the oldest. 0 or less keeps every line.
## Lowering it trims the log at the next append.
@export var max_lines := DEFAULT_MAX_LINES
## Whether the view scrolls to the bottom whenever the scroll range changes (lines added
## or removed, or the view resized), also when the reader had scrolled up.
@export var follow := true
## Font size of new lines; 0 keeps the theme's.
@export var font_size := 0

## The box holding one Label per line, oldest first. Made in `_init`; read it, but add
## lines with `append` so the cap is kept.
var lines: VBoxContainer


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lines = VBoxContainer.new()
	lines.name = _LINES_NAME
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(lines)
	get_v_scroll_bar().changed.connect(_on_range_changed)


## Adds `text` as the newest line (word-wrapped), in `color` when given (a Color, or null
## for the theme's), and drops the oldest lines past `max_lines`. Returns the new line's
## Label, for further styling.
func append(text: String, color: Variant = null) -> Label:
	var line := Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != null:
		line.add_theme_color_override(_FONT_COLOR, color)
	if font_size > 0:
		line.add_theme_font_size_override(_FONT_SIZE, font_size)
	lines.add_child(line)
	if max_lines > 0:
		while lines.get_child_count() > max_lines:
			var oldest := lines.get_child(0)
			lines.remove_child(oldest)
			oldest.queue_free()
	return line


## Removes every line at once.
func clear() -> void:
	for line in lines.get_children():
		lines.remove_child(line)
		line.queue_free()


## Returns the number of lines shown.
func line_count() -> int:
	return lines.get_child_count()


## Returns the text of line `index` (0 is the oldest), or '' when `index` is out of range.
func line_text(index: int) -> String:
	if index < 0 or index >= lines.get_child_count():
		return ''
	return (lines.get_child(index) as Label).text


func _on_range_changed() -> void:
	if follow:
		scroll_vertical = int(get_v_scroll_bar().max_value)
