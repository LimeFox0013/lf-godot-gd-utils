## Lets users tour every on-screen help tip with the keyboard or a gamepad.
##
## Hold a key (F1) or a pad button (Back) to tour every visible `LFHelpTip` on screen.
## The arrows or D-pad (Godot's `ui_*` actions) step through them in reading order,
## wrapping around; each gets a highlight frame and its help panel beside it, plus a
## counter line. Releasing the key closes the tour. `toggle()` opens it for good
## (for an on-screen "Help" button) until toggled again. While the tour is open no
## `LFHelpTip` shows its hover help.
##
## It finds its targets itself, so anything with hover help is browsable with no second
## registration. A full-screen overlay that joins `scope_group` limits the tour to the
## tips inside it while it is visible. Targets are measured on screen (through their
## canvas transform), so tips in another CanvasLayer or under a Camera2D are framed where
## they are drawn. It runs with `PROCESS_MODE_ALWAYS`, so the tour also works while the
## tree is paused.
class_name LFHelpBrowser
extends CanvasLayer

## The tour opened.
signal opened
## The tour closed.
signal closed

## Default `scope_group`.
const DEFAULT_SCOPE_GROUP := &"lf_help_scope"
## Default `row_tolerance_px`, in pixels.
const DEFAULT_ROW_TOLERANCE_PX := 24.0
## Default `gap_px`, in pixels.
const DEFAULT_GAP_PX := 12.0
## Default `frame_pad_px`, in pixels.
const DEFAULT_FRAME_PAD_PX := 4.0

## Upper end of the inspector slider for `row_tolerance_px`, in pixels (larger values can
## be typed).
const _ROW_TOLERANCE_SLIDER_MAX := 200.0
## Upper end of the inspector slider for `gap_px`, in pixels.
const _GAP_SLIDER_MAX := 100.0
## Upper end of the inspector slider for `frame_pad_px`, in pixels.
const _FRAME_PAD_SLIDER_MAX := 50.0
## Inspector slider step for the pixel settings, in pixels.
const _PIXEL_STEP := 1.0
## Canvas layer the tour draws on, above ordinary UI layers.
const _CANVAS_LAYER := 90
## Node name of the `input_layers` child.
const _INPUT_LAYERS_NAME := 'InputLayers'
## Node name of the `frame` child.
const _FRAME_NAME := 'Frame'
## Node name of the `card` child.
const _CARD_NAME := 'Card'
## Theme stylebox name of a Panel / PanelContainer background.
const _PANEL_STYLE := &"panel"
## Project theme type whose `panel` stylebox the card borrows (the tooltip panel).
const _TOOLTIP_PANEL_TYPE := &"TooltipPanel"
## Theme constant name of a box container's spacing.
const _SEPARATION := &"separation"
## Pixels between the help panel and the counter line.
const _CARD_SEPARATION := 6
## Colour of the counter line: white at half opacity.
const _COUNTER_COLOR := Color(1, 1, 1, 0.5)
## Font size of the counter line, in pixels.
const _COUNTER_FONT_SIZE := 11
## Colour of the highlight frame and of the card border.
const _ACCENT := Color(0.95, 0.75, 0.3)
## Border width of the frame and the card, in pixels.
const _BORDER_WIDTH := 2
## Corner radius of the frame and the card, in pixels.
const _CORNER_RADIUS := 6
## Background colour of the fallback card (dark, nearly opaque).
const _CARD_BG := Color(0.1, 0.1, 0.1, 0.95)
## Inner padding of the fallback card, in pixels.
const _CARD_PADDING := 10.0
## Format of the built-in counter line: position (from 1), total, then the close hint.
const _COUNTER_FORMAT := '%d / %d   ←/→ next   %s'
## Close hint of the built-in counter while the tour is held open.
const _HELD_CLOSE_HINT := 'release to close'
## Close hint of the built-in counter while the tour was toggled open.
const _TOGGLED_CLOSE_HINT := 'Help again to close'
## Input actions that step forward through the tour.
const _NEXT_ACTIONS := ['ui_right', 'ui_down']
## Input actions that step back through the tour.
const _PREVIOUS_ACTIONS := ['ui_left', 'ui_up']
## Every stepping action, for releasing an analog push.
const _STEP_ACTIONS := ['ui_right', 'ui_down', 'ui_left', 'ui_up']
## `find_children` pattern matching every node name.
const _ANY_NAME := '*'

## Key that opens the tour while held.
@export var hold_key: Key = KEY_F1
## Pad button that opens the tour while held.
@export var hold_button: JoyButton = JOY_BUTTON_BACK
## Group of full-screen overlays: while one is visible, only the tips inside the last one
## in tree order are browsed.
@export var scope_group: StringName = DEFAULT_SCOPE_GROUP
## Targets whose tops are closer than this (px) count as one row in reading order.
@export_range(0.0, _ROW_TOLERANCE_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var row_tolerance_px := DEFAULT_ROW_TOLERANCE_PX
## Pixels between the target and its help card.
@export_range(0.0, _GAP_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var gap_px := DEFAULT_GAP_PX
## Pixels the highlight frame stands out around the target.
@export_range(0.0, _FRAME_PAD_SLIDER_MAX, _PIXEL_STEP, "or_greater", "suffix:px") var frame_pad_px := DEFAULT_FRAME_PAD_PX
## Box of the highlight frame (drawn without a fill by default).
var frame_style: StyleBox:
	set(value):
		frame_style = value
		frame.add_theme_stylebox_override(_PANEL_STYLE, value)
## Box of the help card; defaults to the project theme's tooltip panel.
var card_style: StyleBox:
	set(value):
		card_style = value
		card.add_theme_stylebox_override(_PANEL_STYLE, value)
## `func(index: int, total: int, held: bool) -> String` for the counter under the help;
## `index` counts from 0 and `held` is whether the tour closes on release. Unset shows
## "2 / 5   ←/→ next   release to close".
var counter_text: Callable

## The highlight frame around the current target.
var frame: Panel
## The card holding the current help panel (child 0 of its box) and the counter.
var card: PanelContainer
## The counter line under the help panel.
var counter_label: Label
## The tip being shown, or null while closed.
var current: LFHelpTip = null
## Reads input before GUI controls (`Stage.INPUT`), so the arrows step through the tour
## instead of moving a control's focus.
var input_layers := LFInputManager.new()

var _is_open := false
var _held_open := false
var _content: Control = null
var _input_layer := 0
## Stepping actions an analog stick holds pushed past the deadzone: one push steps once.
var _pushed_actions := {}


func _init() -> void:
	layer = _CANVAS_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	input_layers.name = _INPUT_LAYERS_NAME
	input_layers.stage = LFInputManager.Stage.INPUT
	add_child(input_layers)
	frame = Panel.new()
	frame.name = _FRAME_NAME
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	add_child(frame)
	card = PanelContainer.new()
	card.name = _CARD_NAME
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(_SEPARATION, _CARD_SEPARATION)
	card.add_child(box)
	counter_label = LFBuild.label(box, '', _COUNTER_COLOR, _COUNTER_FONT_SIZE)
	frame_style = LFStyle.outline(_ACCENT, _BORDER_WIDTH, _CORNER_RADIUS)
	card_style = LFStyle.project_stylebox(_PANEL_STYLE, _TOOLTIP_PANEL_TYPE, LFStyle.flat(_CARD_BG, _ACCENT, _BORDER_WIDTH, _CORNER_RADIUS, _CARD_PADDING))


## The input layer lasts while its owner stays in the tree, so it is added on every entry.
## Leaving the tree closes an open tour: it could not be closed by key from outside.
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not input_layers.has_layer(_input_layer):
		_input_layer = input_layers.add_layer(self, _on_input)
	elif what == NOTIFICATION_EXIT_TREE:
		close()


## Whether the tour is showing.
func is_open() -> bool:
	return _is_open


## Whether the tour was opened by holding the key or button (and closes on release).
func is_held_open() -> bool:
	return _is_open and _held_open


## Opens the tour when closed, closes it when open: what an on-screen Help button calls.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Opens the tour on the first target in reading order, closing any tip's hover help (no
## tip shows one while the tour is open). Does nothing when already open or when there is
## nothing to explain.
func open() -> void:
	if _is_open:
		return
	var targets := visible_targets()
	if targets.is_empty():
		return
	_is_open = true
	# While the tour is open no tip shows its hover help: the card already shows one.
	add_to_group(LFHelpTip._BROWSING_GROUP)
	get_tree().call_group(LFHelpTip._TIPS_GROUP, &"_hide_help")
	_show(targets[0])
	opened.emit()


## Closes the tour and hides the frame and card.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_held_open = false
	remove_from_group(LFHelpTip._BROWSING_GROUP)
	current = null
	frame.visible = false
	card.visible = false
	closed.emit()


## Moves `delta` places through the reading order, wrapping around. Closes the tour when
## no target is left. Does nothing while the tour is closed.
func step(delta: int) -> void:
	if not _is_open:
		return
	var targets := visible_targets()
	if targets.is_empty():
		close()
		return
	var index := targets.find(current)
	index = 0 if index == -1 else posmod(index + delta, targets.size())
	_show(targets[index])


## Every help tip on screen, in reading order of their targets
## (`LFControl.sort_reading_order` on the controls the tips explain): visible in the tree,
## with an area, overlapping the viewport's visible rect on screen (`LFHelpTip.get_help_rect`,
## the target's `LFControl.get_canvas_rect`), and inside the topmost visible `scope_group`
## overlay when there is one.
func visible_targets() -> Array[LFHelpTip]:
	var found: Array[LFHelpTip] = []
	if not is_inside_tree():
		return found
	var screen := get_viewport().get_visible_rect()
	var scope: Node = get_tree().root
	for node in get_tree().get_nodes_in_group(scope_group):
		if node is CanvasItem and node.is_visible_in_tree():
			scope = node
	var tip_of := {}
	for node in scope.find_children(_ANY_NAME, '', true, false):
		var tip := node as LFHelpTip
		if tip == null or tip.is_queued_for_deletion() or not tip.is_visible_in_tree():
			continue
		var target := tip.get_parent() as Control
		if target == null:
			continue
		var rect := tip.get_help_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0 or not screen.intersects(rect):
			continue
		tip_of[target] = tip
	for target: Control in LFControl.sort_reading_order(tip_of.keys(), row_tolerance_px):
		found.append(tip_of[target])
	return found


## The counter line for target `index` (from 0) of `total`; `held` is whether the tour
## closes on release. Uses `counter_text` when set, else the built-in English line.
func format_counter(index: int, total: int, held: bool) -> String:
	if counter_text.is_valid():
		return str(counter_text.call(index, total, held))
	return _COUNTER_FORMAT % [index + 1, total, _HELD_CLOSE_HINT if held else _TOGGLED_CLOSE_HINT]


## The rect of `tip` on this browser's layer: its on-screen rect (for an `LFHelpTip`, its
## `get_help_rect`) mapped through this layer's own transform (identity unless `offset`,
## `scale` or `follow_viewport` are set).
func rect_on_layer(tip: Control) -> Rect2:
	var help_tip := tip as LFHelpTip
	var rect := help_tip.get_help_rect() if help_tip != null else LFControl.get_canvas_rect(tip)
	return get_final_transform().affine_inverse() * rect


## Takes the hold key or button (every press, and while open every event of it), and the
## arrows while open; true when it took the event. A stick push past the deadzone steps
## once, and steps again only after it falls back below the deadzone.
func _on_input(event: InputEvent) -> bool:
	if _is_hold_event(event):
		if event.is_pressed() and not event.is_echo():
			if not _is_open:
				_held_open = true
				open()
				_held_open = _is_open
			return true
		if not event.is_pressed() and _held_open:
			close()
			return true
		return _is_open
	if event is InputEventJoypadMotion:
		return _on_stick(event)
	if not _is_open or not event.is_pressed():
		return false
	if _is_any_action(event, _NEXT_ACTIONS):
		step(1)
		return true
	if _is_any_action(event, _PREVIOUS_ACTIONS):
		step(-1)
		return true
	return false


## A stick sends a pressed event every time it moves past the deadzone, so a push is
## latched per action until the action is released.
func _on_stick(event: InputEventJoypadMotion) -> bool:
	for action: String in _STEP_ACTIONS:
		if event.is_action_released(action):
			_pushed_actions.erase(action)
	if not _is_open:
		return false
	for action: String in _STEP_ACTIONS:
		if not event.is_action_pressed(action):
			continue
		if not _pushed_actions.has(action):
			_pushed_actions[action] = true
			step(1 if _NEXT_ACTIONS.has(action) else -1)
		return true
	return false


static func _is_any_action(event: InputEvent, actions: Array) -> bool:
	return actions.any(func(action: String) -> bool: return event.is_action(action))


func _is_hold_event(event: InputEvent) -> bool:
	return (event is InputEventKey and (event.keycode == hold_key or (event.keycode == KEY_NONE and event.physical_keycode == hold_key))) \
		or (event is InputEventJoypadButton and event.button_index == hold_button)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	# A target can vanish (its screen was hidden): move on rather than point at nothing.
	if current == null or not is_instance_valid(current) or not current.is_visible_in_tree():
		var targets := visible_targets()
		if targets.is_empty():
			close()
			return
		_show(targets[0])
		return
	_place()


func _show(tip: LFHelpTip) -> void:
	current = tip
	if _content != null and is_instance_valid(_content):
		_content.get_parent().remove_child(_content)
		_content.queue_free()
	_content = tip.build_panel()
	if _content == null:
		_content = LFBuild.label(null, tip.tooltip_text)
	var box := card.get_child(0)
	box.add_child(_content)
	box.move_child(_content, 0)
	var targets := visible_targets()
	counter_label.text = format_counter(targets.find(tip), targets.size(), _held_open)
	frame.visible = true
	card.visible = true
	card.reset_size()
	_place()


## The frame hugs the target; the card sits beside it (`LFControl.place_beside`).
func _place() -> void:
	var rect := rect_on_layer(current).grow(frame_pad_px)
	frame.position = rect.position
	frame.size = rect.size
	card.position = LFControl.place_beside(rect, card.get_combined_minimum_size(), get_viewport().get_visible_rect().size, gap_px)
