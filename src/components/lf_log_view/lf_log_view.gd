## A scrolling list of text lines, such as an activity log or a debug console.
##
## `append` adds a line at the bottom, the oldest lines are dropped past `max_lines`, and
## while `follow` is on the view scrolls to the bottom whenever its scroll range changes. By
## default each line is a Label; set `line_scene` or `line_factory` to make each line a control
## of your own (a chat bubble, say) and keep the cap and the scrolling. Line i is child i of
## `lines`, oldest first.
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
## Property a `line_scene` root is given the line's text through, when it has one.
const _TEXT_PROPERTY := &"text"
## Metadata key every line carries its text under, for `line_text`.
const _TEXT_META := &"lf_log_view_text"

## Most lines kept; appending past it drops the oldest. 0 or less keeps every line.
## Lowering it trims the log at the next append.
@export var max_lines := DEFAULT_MAX_LINES
## Whether the view scrolls to the bottom whenever the scroll range changes (lines added
## or removed, or the view resized), also when the reader had scrolled up.
@export var follow := true
## Font size of new lines; 0 keeps the theme's.
@export var font_size := 0

## Makes each new line from this scene instead of a Label. Its root must be a Control.
## The line's text goes to the root's `text` property when it has one (a Label does, so
## does a script with `var text`); the colour given to `append` is applied to a Label root
## as its font colour and otherwise ignored. Null keeps the plain Label. Ignored while
## `line_factory` is valid.
@export var line_scene: PackedScene
## Makes each new line by calling `func(text: String, color: Variant) -> Control` (`color`
## is a Color or null), for lines that need more than a `text` property. The Control it
## returns is added as the line; `font_size` is not applied to it. A Callable that is not
## valid keeps the other options. If it returns anything but a Control, the error is reported through `LFLogger` and a plain Label is used.
var line_factory := Callable()

## The box holding one control per line (a Label by default), oldest first. Made in `_init`; read it, but add
## lines with `append` so the cap is kept.
var lines: VBoxContainer

static var _log := LFLogger.new(['LFLogView'])


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lines = VBoxContainer.new()
	lines.name = _LINES_NAME
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(lines)
	get_v_scroll_bar().changed.connect(_on_range_changed)


## Adds `text` as the newest line (a word-wrapped Label unless `line_factory` or
## `line_scene` is set), in `color` when given (a Color, or null for the theme's), and drops
## the oldest lines past `max_lines`. Returns the new line's control, for further styling.
func append(text: String, color: Variant = null) -> Control:
	var line := _make_line(text, color)
	line.set_meta(_TEXT_META, text)
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


## Returns the text line `index` (0 is the oldest) was appended with, or '' when `index`
## is out of range.
func line_text(index: int) -> String:
	if index < 0 or index >= lines.get_child_count():
		return ''
	var line := lines.get_child(index)
	if line.has_meta(_TEXT_META):
		return line.get_meta(_TEXT_META)
	return (line as Label).text if line is Label else ''


func _make_line(text: String, color: Variant) -> Control:
	if line_factory.is_valid():
		var made: Variant = line_factory.call(text, color)
		if made is Control:
			return made
		_log.error('line_factory must return a Control')
	elif line_scene != null:
		var root := line_scene.instantiate()
		if root is Control:
			if _TEXT_PROPERTY in root:
				root.set(_TEXT_PROPERTY, text)
			if color != null and root is Label:
				root.add_theme_color_override(_FONT_COLOR, color)
			return root
		_log.error('line_scene must have a Control as its root')
		root.free()
	return _make_label(text, color)


func _make_label(text: String, color: Variant) -> Label:
	var line := Label.new()
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != null:
		line.add_theme_color_override(_FONT_COLOR, color)
	if font_size > 0:
		line.add_theme_font_size_override(_FONT_SIZE, font_size)
	return line


func _on_range_changed() -> void:
	if follow:
		scroll_vertical = int(get_v_scroll_bar().max_value)
