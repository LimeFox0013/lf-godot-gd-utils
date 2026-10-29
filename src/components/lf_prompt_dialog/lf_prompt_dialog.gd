## An awaitable text prompt: `var name: String = await LFPromptDialog.ask(parent, "Name your save", "Type a name")`.
##
## `ask` builds a modal popup (a dimmed screen with a centered panel holding a title, a
## one-line text field, an OK button and a Cancel button), adds it to `parent`, waits and
## frees the popup. It returns what was typed, or `""` when the player cancels (Cancel
## button, Escape) or `parent` is freed or leaves the scene tree first. The OK button stays disabled
## while the field is empty (with `trim`, also while it holds only spaces), and Enter in
## the field does what OK does, so an empty text is never returned for OK: `""` always means "cancelled".
## The popup draws on its own `CanvasLayer` and blocks mouse clicks to everything under it.
class_name LFPromptDialog
extends CanvasLayer

## Emitted once, when the popup is answered: the text, or `""` when cancelled.
signal answered(text: String)

## Default text of the OK button.
const DEFAULT_OK_TEXT := 'OK'
## Default text of the Cancel button.
const DEFAULT_CANCEL_TEXT := 'Cancel'
## Default `layer`: above ordinary HUD layers.
const DEFAULT_LAYER := 100
## Default colour drawn over everything behind the popup.
const DEFAULT_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.6)
## Minimum width in pixels of the text field.
const FIELD_WIDTH := 320.0
## Pixels between the rows of the panel and between the two buttons.
const SEPARATION := 12
## Theme font size of the title.
const TITLE_FONT_SIZE := 20
## Node name of the dimming rectangle.
const _DIM_NAME := 'Dim'
## Node name of the panel.
const _PANEL_NAME := 'Panel'
## Node name of the OK button.
const _OK_NAME := 'OkButton'
## Node name of the Cancel button.
const _CANCEL_NAME := 'CancelButton'
## Input action that cancels.
const _CANCEL_ACTION := &"ui_cancel"

## The title label. Made in `_init`.
var title_label: Label
## The text field. Made in `_init`.
var edit: LineEdit
## The OK button. Made in `_init`.
var ok_button: Button
## The Cancel button. Made in `_init`.
var cancel_button: Button
## Whether spaces around the text are ignored: they do not count as text for enabling OK, and are cut from the result.
var trim := true:
	set(value):
		trim = value
		_refresh()

var _done := false

static var _log := LFLogger.new(['LFPromptDialog'])


func _init() -> void:
	layer = DEFAULT_LAYER
	var dim := ColorRect.new()
	dim.name = _DIM_NAME
	dim.color = DEFAULT_DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.name = _PANEL_NAME
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", SEPARATION)
	panel.add_child(box)
	title_label = LFBuild.label(box, '', null, TITLE_FONT_SIZE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit = LFBuild.line_edit(box)
	edit.custom_minimum_size.x = FIELD_WIDTH
	edit.text_changed.connect(_on_text_changed)
	edit.text_submitted.connect(_on_text_submitted)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", SEPARATION)
	box.add_child(row)
	ok_button = LFBuild.button(row, DEFAULT_OK_TEXT, submit)
	ok_button.name = _OK_NAME
	cancel_button = LFBuild.button(row, DEFAULT_CANCEL_TEXT, cancel)
	cancel_button.name = _CANCEL_NAME
	_refresh()


## Shows a prompt under `parent` and returns the text typed once OK (or Enter) is
## pressed, cut of surrounding spaces when `trim`. Returns `""` when cancelled, when `parent`
## is freed or leaves the scene tree first, and at once (with an error through `LFLogger`)
## when `parent` is null, freed or not in the scene tree. `initial_text` fills the field first.
## The popup frees itself.
static func ask(
	parent: Node,
	title: String,
	placeholder := '',
	ok_text := DEFAULT_OK_TEXT,
	cancel_text := DEFAULT_CANCEL_TEXT,
	trim_text := true,
	initial_text := '',
) -> String:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		_log.error('ask needs a parent that is inside the scene tree')
		return ''
	var popup := LFPromptDialog.new()
	popup.trim = trim_text
	popup.title_label.text = title
	popup.edit.placeholder_text = placeholder
	popup.edit.text = initial_text
	popup.ok_button.text = ok_text
	popup.cancel_button.text = cancel_text
	popup._refresh()
	parent.add_child(popup)
	# A freed parent frees the popup with it: _exit_tree then answers "".
	var text: String = await popup.answered
	return text


## What the field holds now, cut of surrounding spaces when `trim`.
func current_text() -> String:
	return edit.text.strip_edges() if trim else edit.text


## Whether OK would be accepted now: the current text is not empty.
func can_submit() -> bool:
	return current_text() != ''


## What OK does: answers with the current text. Nothing while `can_submit` is false.
func submit() -> void:
	if can_submit():
		_finish(current_text())


## What Cancel and Escape do: answers `""`.
func cancel() -> void:
	_finish('')


func _ready() -> void:
	edit.grab_focus()


func _exit_tree() -> void:
	_finish('')


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		cancel()


func _finish(text: String) -> void:
	if _done:
		return
	_done = true
	answered.emit(text)
	queue_free()


func _refresh() -> void:
	if ok_button != null:
		ok_button.disabled = not can_submit()


func _on_text_changed(_text: String) -> void:
	_refresh()


func _on_text_submitted(_text: String) -> void:
	submit()
