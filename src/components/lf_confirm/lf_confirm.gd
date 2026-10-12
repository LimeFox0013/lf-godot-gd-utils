## An awaitable yes/no popup: `var ok: bool = await LFConfirm.ask(parent, "Quit?", "Lose progress?")`.
##
## `ask` builds a modal popup (a dimmed screen with a centered panel holding a title, a
## message and two buttons), adds it to `parent`, waits for the answer and frees the popup.
## It answers `true` for Yes, and `false` for No, for the Escape key (`ui_cancel`), and when
## `parent` is freed (or leaves the scene tree) before an answer. The popup draws on its own
## `CanvasLayer`, so it covers the whole window whatever `parent` is, and it blocks mouse
## clicks to everything under it. The "No" button has the keyboard focus unless
## `focus_yes_button` is set, so pressing Enter or Space right away does not confirm a risky action by accident.
class_name LFConfirm
extends CanvasLayer

## Emitted once, when the popup is answered: `true` for Yes, `false` for No, Escape or a freed parent.
signal answered(ok: bool)

## Default text of the Yes button.
const DEFAULT_YES_TEXT := 'Yes'
## Default text of the No button.
const DEFAULT_NO_TEXT := 'No'
## Default `layer`: above ordinary HUD layers.
const DEFAULT_LAYER := 100
## Default colour drawn over everything behind the popup.
const DEFAULT_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.6)
## Width in pixels the message wraps at.
const TEXT_WIDTH := 320.0
## Pixels between the rows of the panel and between the two buttons.
const SEPARATION := 12
## Theme font size of the title; 0 would keep the theme's.
const TITLE_FONT_SIZE := 20
## Node name of the dimming rectangle.
const _DIM_NAME := 'Dim'
## Node name of the panel.
const _PANEL_NAME := 'Panel'
## Node name of the Yes button.
const _YES_NAME := 'YesButton'
## Node name of the No button.
const _NO_NAME := 'NoButton'
## Input action that answers No.
const _CANCEL_ACTION := &"ui_cancel"

## The title label. Made in `_init`.
var title_label: Label
## The message label. Made in `_init`.
var text_label: Label
## The Yes button. Made in `_init`.
var yes_button: Button
## The No button. Made in `_init`.
var no_button: Button
## Whether the Yes button, rather than No, takes the focus when the popup opens.
var focus_yes := false

var _done := false

static var _log := LFLogger.new(['LFConfirm'])


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
	text_label = LFBuild.wrap(LFBuild.label(box), TEXT_WIDTH)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", SEPARATION)
	box.add_child(row)
	yes_button = LFBuild.button(row, DEFAULT_YES_TEXT, answer.bind(true))
	yes_button.name = _YES_NAME
	no_button = LFBuild.button(row, DEFAULT_NO_TEXT, answer.bind(false))
	no_button.name = _NO_NAME


## Shows a popup under `parent` and returns the answer once it is given: `true` for Yes;
## `false` for No, Escape, or when `parent` is freed or leaves the scene tree first. Also
## `false` at once (with an error through `LFLogger`) when `parent` is null, freed or not
## in the scene tree. "No" has the focus unless `focus_yes_button`. The popup frees itself.
static func ask(
	parent: Node,
	title: String,
	text: String,
	yes_text := DEFAULT_YES_TEXT,
	no_text := DEFAULT_NO_TEXT,
	focus_yes_button := false,
) -> bool:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		_log.error('ask needs a parent that is inside the scene tree')
		return false
	var popup := LFConfirm.new()
	popup.focus_yes = focus_yes_button
	popup.title_label.text = title
	popup.text_label.text = text
	popup.yes_button.text = yes_text
	popup.no_button.text = no_text
	parent.add_child(popup)
	# A freed parent frees the popup with it: _exit_tree then answers false.
	var ok: bool = await popup.answered
	return ok


## Gives the answer: emits `answered` and frees the popup. Only the first call counts.
func answer(ok: bool) -> void:
	if _done:
		return
	_done = true
	answered.emit(ok)
	queue_free()


func _ready() -> void:
	(yes_button if focus_yes else no_button).grab_focus()


func _exit_tree() -> void:
	answer(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(_CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		answer(false)
