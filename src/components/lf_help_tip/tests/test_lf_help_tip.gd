extends GutTest

## Hovering a control opens a tooltip window with a panel built from its help content; the
## tip takes no part in mouse picking, so the control, its children and whatever is drawn
## over it keep their hover and clicks.


class Entry:
	extends RefCounted
	var title: String
	var explanation: String
	var example: String

	func _init(title_text: String, explanation_text: String, example_text := '') -> void:
		title = title_text
		explanation = explanation_text
		example = example_text


static func _three_part(entry: Entry) -> Control:
	var box := VBoxContainer.new()
	LFBuild.label(box, entry.title)
	LFBuild.label(box, entry.explanation)
	var example := LFBuild.label(box, entry.example)
	example.visible = entry.example != ''
	return box


func _entry() -> Entry:
	return Entry.new('tip_a', 'Explains item a.', 'e.g. an example of item a.')


## The headless window is 64 x 64 px; lay the GUI out on a fixed 1152 x 648 screen instead,
## whatever the project's stretch settings, and put them back afterwards.
const SCREEN := Vector2i(1152, 648)
var _saved_scale: Array


func _pin_screen() -> void:
	var window := get_tree().root
	_saved_scale = [window.content_scale_mode, window.content_scale_aspect, window.content_scale_size]
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = SCREEN


func _unpin_screen() -> void:
	var window := get_tree().root
	window.content_scale_mode = _saved_scale[0]
	window.content_scale_aspect = _saved_scale[1]
	window.content_scale_size = _saved_scale[2]


## The tooltip delay the tests run with, in seconds, instead of the project's 0.5 s.
const DELAY_SEC := 0.05
## Longest a test waits for help to show, in seconds: a cap, not an expected time.
const SHOW_WAIT_SEC := 2.0
## How long a test waits before checking that help did NOT show, in seconds (four delays).
const NOT_SHOWN_WAIT_SEC := 0.2
var _saved_delay: Variant

## GUT's own runner GUI sits on a canvas layer above everything and would take the mouse
## in the hover tests; it is hidden while each test runs.
var _hidden_layers: Array[CanvasLayer] = []


func before_each():
	_pin_screen()
	_saved_delay = ProjectSettings.get_setting('gui/timers/tooltip_delay_sec')
	ProjectSettings.set_setting('gui/timers/tooltip_delay_sec', DELAY_SEC)
	for node in get_tree().root.find_children('*', 'CanvasLayer', true, false):
		var layer := node as CanvasLayer
		if layer.visible:
			layer.visible = false
			_hidden_layers.append(layer)


func after_each():
	if get_tree().paused:
		get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	# Move the mouse off every test control, then let replaced panels and tips go.
	await _hover(Vector2(1, 1))
	await wait_process_frames(1)
	LFHelpTip.default_builder = Callable()
	ProjectSettings.set_setting('gui/timers/tooltip_delay_sec', _saved_delay)
	for layer in _hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_layers.clear()
	_unpin_screen()


## Moves the mouse to `at` (viewport pixels) through the viewport, as a real mouse does.
func _hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	get_viewport().push_input(event, true)
	await wait_process_frames(1)


## Presses and releases the left mouse button at `at` (viewport pixels) through the viewport.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
		await wait_process_frames(1)


## Waits until `tip` shows its help (at most SHOW_WAIT_SEC) and returns its window.
func _shown(tip: LFHelpTip) -> PopupPanel:
	await wait_until(func() -> bool: return tip.get_popup() != null, SHOW_WAIT_SEC)
	return tip.get_popup()


## Whether `tip` shows its help after waiting well past the delay.
func _shows_after_the_delay(tip: LFHelpTip) -> bool:
	await wait_seconds(NOT_SHOWN_WAIT_SEC)
	return tip.get_popup() != null


## Where hover tests put their controls.
const HOVER_AREA := Vector2(400, 300)


## A row of [label][button][label] with a gap between items, tipped as a whole.
func _tipped_row(parent: Node = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position = HOVER_AREA
	row.add_theme_constant_override(&"separation", 20)
	for i in 3:
		var item: Control = Button.new() if i == 1 else Label.new()
		item.set(&"text", 'item %d' % i)
		row.add_child(item)
	if parent == null:
		add_child_autofree(row)
	else:
		parent.add_child(row)
	LFHelpTip.attach(row, 'About the row.')
	return row


## Hover tests on a [Panel] at HOVER_AREA, 300 x 100, holding `child` at (20, 20).
func _tipped_panel(child: Control) -> LFHelpTip:
	var panel: Panel = add_child_autofree(Panel.new())
	panel.position = HOVER_AREA
	panel.size = Vector2(300, 100)
	child.position = Vector2(20, 20)
	child.size = Vector2(80, 30)
	panel.add_child(child)
	return LFHelpTip.attach(panel, 'About the panel.')


func test_attach_adds_one_tip_that_never_takes_the_mouse():
	var label: Label = add_child_autofree(Label.new())

	var tip := LFHelpTip.attach(label, _entry(), _three_part)

	assert_eq(LFHelpTip.of(label), tip)
	assert_eq(tip.get_parent(), label)
	assert_eq(tip.mouse_filter, Control.MOUSE_FILTER_IGNORE, 'never picked')
	assert_true(tip.top_level)
	assert_eq(tip.size, Vector2.ZERO)
	assert_eq(tip.tooltip_text, 'tip_a', 'the content title')
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, 'the target keeps ignoring the mouse')
	assert_eq(label.tooltip_text, '', 'an ignoring target needs no blank tooltip')


func test_a_target_that_takes_the_mouse_keeps_its_filter_and_gets_a_blank_tooltip():
	var button: Button = add_child_autofree(Button.new())
	var row: HBoxContainer = add_child_autofree(HBoxContainer.new())
	var described: Button = add_child_autofree(Button.new())
	described.tooltip_text = 'Its own text.'

	LFHelpTip.attach(button, 'x')
	LFHelpTip.attach(row, 'y')
	LFHelpTip.attach(described, 'z')

	assert_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_eq(button.tooltip_text, ' ')
	assert_eq(row.tooltip_text, ' ')
	assert_eq(described.tooltip_text, 'Its own text.', 'tooltip text of its own is kept')


func test_removing_a_tip_puts_back_the_empty_tooltip_it_blanked():
	var button: Button = add_child_autofree(Button.new())
	var other: Button = add_child_autofree(Button.new())
	var tip := LFHelpTip.attach(button, 'x')

	LFHelpTip.attach_tip(other, tip)
	assert_eq(button.tooltip_text, '', 'moved away: put back')
	assert_eq(other.tooltip_text, ' ')
	tip.free()
	assert_eq(other.tooltip_text, '', 'freed: put back')
	LFHelpTip.attach(button, 'y')
	LFHelpTip.attach(button, 'z')
	assert_eq(button.tooltip_text, ' ', 'a replaced tip leaves the blank to the new one')


## Code that empties the tooltip after attaching (a refresh that sets
## `tooltip_text = ''`) would let a parent's plain tooltip open over the help again.
func test_a_tooltip_emptied_after_attaching_is_blanked_again_on_hover():
	var tile: Button = add_child_autofree(Button.new())
	tile.position = HOVER_AREA
	tile.size = Vector2(200, 100)
	tile.tooltip_text = 'The tile description.'
	var level := Label.new()
	level.text = 'Level 2'
	level.mouse_filter = Control.MOUSE_FILTER_PASS
	level.position = Vector2(10, 10)
	tile.add_child(level)
	var tip := LFHelpTip.attach(level, 'What a level is.')
	level.tooltip_text = ''
	await wait_process_frames(2)

	await _hover(level.get_global_rect().get_center())
	await _shown(tip)
	await wait_seconds(GODOT_TOOLTIP_WAIT_SEC)

	assert_eq(level.tooltip_text, ' ')
	assert_eq(_open_tooltip_windows(), [tip.get_popup()] as Array[Window])


func test_attaching_again_replaces_rather_than_stacks():
	var label: Label = add_child_autofree(Label.new())
	LFHelpTip.attach(label, _entry())

	var second := LFHelpTip.attach(label, Entry.new('Other', 'x', 'y'))

	var tips := label.get_children().filter(func(c): return c is LFHelpTip)
	assert_eq(tips, [second])
	assert_eq(LFHelpTip.of(label), second)


func test_null_content_attaches_nothing():
	var label: Label = add_child_autofree(Label.new())

	assert_null(LFHelpTip.attach(label, null))
	assert_null(LFHelpTip.of(label))


func test_hovering_a_tipped_label_shows_the_built_panel_in_a_tooltip_window():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'Gold: 120'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, _entry(), _three_part)
	await wait_process_frames(2)
	var at := label.get_global_rect().get_center()

	await _hover(at)
	var popup := await _shown(tip)

	assert_not_null(popup)
	assert_true(popup.visible)
	assert_eq(popup.theme_type_variation, &"TooltipPanel", 'the look of Godot tooltips')
	assert_true(popup.mouse_passthrough, 'the window never takes the mouse')
	var panel: Control = popup.get_child(0)
	assert_eq((panel.get_child(0) as Label).text, 'tip_a')
	assert_eq((panel.get_child(1) as Label).text, 'Explains item a.')
	assert_eq((panel.get_child(2) as Label).text, 'e.g. an example of item a.')
	var offset: Vector2 = ProjectSettings.get_setting('display/mouse_cursor/tooltip_position_offset')
	assert_eq(popup.position, Vector2i(at + offset), 'at the mouse plus the project offset')


func test_moving_off_the_target_hides_its_help():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'Gold: 120'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, 'Spent at the merchant.')
	await wait_process_frames(2)
	await _hover(label.get_global_rect().get_center())
	var popup := await _shown(tip)

	await _hover(label.get_global_rect().end + Vector2(30, 30))

	assert_null(tip.get_popup())
	assert_false(is_instance_valid(popup) and popup.visible)


func test_a_click_hides_the_help_and_still_reaches_the_target():
	var button: Button = add_child_autofree(Button.new())
	button.text = 'Buy'
	button.position = HOVER_AREA
	button.size = Vector2(120, 40)
	var tip := LFHelpTip.attach(button, 'Buys one sword.')
	var presses := []
	button.pressed.connect(func(): presses.append(true))
	await wait_process_frames(2)
	var at := button.get_global_rect().get_center()
	await _hover(at)
	await _shown(tip)

	await _click(at)

	assert_eq(presses.size(), 1)
	assert_null(tip.get_popup())
	assert_eq(get_viewport().gui_get_hovered_control(), button, 'the button keeps its hover style')


func test_an_empty_example_hides_its_line():
	var label: Label = add_child_autofree(Label.new())
	var tip := LFHelpTip.attach(label, Entry.new('T', 'E'), _three_part)

	var panel: Control = autofree(tip.build_panel())

	assert_false(panel.get_child(2).visible)


func test_without_a_builder_the_default_builder_is_used():
	var label: Label = add_child_autofree(Label.new())
	LFHelpTip.default_builder = func(entry): return LFBuild.label(null, 'default: ' + entry.title)
	var tip := LFHelpTip.attach(label, _entry())

	var panel: Label = autofree(tip.build_panel())

	assert_eq(panel.text, 'default: tip_a')


func test_text_content_needs_no_builder():
	var label: Label = add_child_autofree(Label.new())
	var tip := LFHelpTip.attach(label, 'A plain text tip.')

	var panel: Label = autofree(tip.build_panel())

	assert_eq(tip.tooltip_text, 'A plain text tip.')
	assert_eq(panel.text, 'A plain text tip.')
	assert_eq(panel.custom_minimum_size.x, LFHelpTip.TEXT_WIDTH)


func test_a_builder_giving_no_panel_shows_the_hover_text_as_a_tooltip_label():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'x'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, _entry(), func(_c): return null, 'Plain hover text')
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())
	var popup := await _shown(tip)

	var shown: Label = popup.get_child(0)
	assert_eq(shown.text, 'Plain hover text')
	assert_eq(shown.theme_type_variation, &"TooltipLabel")


func test_with_no_panel_and_blank_hover_text_nothing_shows():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'x'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, 42, func(_c): return null)
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())

	assert_false(await _shows_after_the_delay(tip))


func test_hover_text_can_be_given_or_read_from_the_content():
	var label: Label = add_child_autofree(Label.new())

	assert_eq(LFHelpTip.attach(label, _entry(), Callable(), 'Hover text').tooltip_text, 'Hover text')
	assert_eq(LFHelpTip.hover_text_of({'title': 'item_a'}), 'item_a')
	assert_eq(LFHelpTip.hover_text_of(Entry.new('item_a', 'x')), 'item_a')
	assert_eq(LFHelpTip.hover_text_of(&"Name"), 'Name')
	assert_eq(LFHelpTip.hover_text_of(42), '', 'no title')


func test_attach_tip_installs_a_ready_made_tip():
	var label: Label = add_child_autofree(Label.new())
	LFHelpTip.attach(label, _entry())
	var mine := LFHelpTip.new()
	mine.content = 'custom'

	assert_eq(LFHelpTip.attach_tip(label, mine), mine)

	assert_eq(label.get_children().filter(func(c): return c is LFHelpTip), [mine])
	assert_eq(mine.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(mine.tooltip_text, 'custom')


## A real click routed by the viewport onto a tipped Button still presses it.
func test_a_click_on_a_tipped_button_still_presses_it():
	var button: Button = add_child_autofree(Button.new())
	button.position = Vector2(40, 40)
	button.size = Vector2(120, 40)
	LFHelpTip.attach(button, _entry())
	var presses := []
	button.pressed.connect(func(): presses.append(true))
	await wait_process_frames(1)

	# Without `in_local_coords` the viewport routes no synthetic click to the GUI.
	await _click(button.get_global_rect().get_center())

	assert_eq(presses.size(), 1)


func test_no_content_builds_no_panel():
	var tip: LFHelpTip = autofree(LFHelpTip.new())

	assert_null(tip.build_panel())


## A container lays out its children; the tip must not become one more (zero-width) item.
func test_a_tip_on_a_container_is_not_laid_out_as_an_item():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)

	assert_true(tip.top_level, 'a container ignores top-level children when it sorts')
	assert_eq(row.get_child(1).get_index(), 1)
	assert_eq(row.get_child(2).position.x - row.get_child(1).get_rect().end.x, 20.0, 'no extra separation for a hidden item')


func test_a_button_inside_a_tipped_container_keeps_its_hover_and_no_help_shows():
	var row := _tipped_row()
	var button: Button = row.get_child(1)
	await wait_process_frames(2)

	await _hover(button.get_global_rect().get_center())

	assert_eq(get_viewport().gui_get_hovered_control(), button)
	assert_false(await _shows_after_the_delay(LFHelpTip.of(row)), 'the button stops the mouse, so the row is not hovered')


func test_hovering_the_rest_of_a_tipped_container_shows_its_help():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	var label: Label = row.get_child(0)
	var gap := Vector2(row.get_child(1).get_global_rect().end.x + 10.0, row.get_global_rect().get_center().y)

	await _hover(label.get_global_rect().get_center())
	assert_not_null(await _shown(tip), 'over a label (which ignores the mouse)')
	await _hover(row.get_global_rect().end + Vector2(10, 10))
	assert_null(tip.get_popup(), 'outside the row')
	await _hover(gap)
	assert_not_null(await _shown(tip), 'over the gap between items')


func test_a_tipped_container_follows_its_target_when_it_moves_without_per_frame_work():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)

	row.position = Vector2(300, 200)
	(row.get_child(0) as Label).text = 'a much longer item text'
	await wait_process_frames(2)
	await _hover(row.get_child(0).get_global_rect().get_center())

	assert_false(tip.is_processing(), 'no _process')
	assert_false(tip.is_physics_processing())
	assert_not_null(await _shown(tip), 'hover follows the moved row')
	assert_eq(tip.get_help_rect(), LFControl.get_canvas_rect(row))


func test_a_tipped_container_clipped_by_an_ancestor_shows_no_help_outside_the_clip():
	var clip: Control = add_child_autofree(Control.new())
	clip.clip_contents = true
	clip.position = HOVER_AREA
	clip.size = Vector2(30, 200)
	var row := _tipped_row(clip)
	row.position = Vector2.ZERO
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	var y := row.get_global_rect().get_center().y

	await _hover(Vector2(clip.get_global_rect().end.x + 5.0, y))
	assert_false(await _shows_after_the_delay(tip), 'the clipped-away part of the row')
	await _hover(Vector2(HOVER_AREA.x + 10.0, y))
	assert_not_null(await _shown(tip), 'inside the clip')


func test_a_button_inside_a_tipped_container_still_presses():
	var row := _tipped_row()
	var button: Button = row.get_child(1)
	var presses := []
	button.pressed.connect(func(): presses.append(true))
	await wait_process_frames(2)

	await _click(button.get_global_rect().get_center())

	assert_eq(presses.size(), 1)


func test_a_tip_on_a_plain_control_is_the_same_kind_of_tip_and_does_not_process():
	var label: Label = add_child_autofree(Label.new())

	var tip := LFHelpTip.attach(label, 'x')
	await wait_process_frames(1)

	assert_true(tip.top_level)
	assert_eq(tip.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(tip.is_processing())
	assert_false(tip.is_physics_processing())
	assert_eq(tip.get_help_rect(), LFControl.get_canvas_rect(label))


func test_a_null_target_is_reported_and_attaches_nothing():
	assert_null(LFHelpTip.attach(null, 'x'))
	assert_push_error('LFHelpTip')
	var tip: LFHelpTip = autofree(LFHelpTip.new())
	assert_null(LFHelpTip.attach_tip(null, tip))
	assert_push_error('LFHelpTip')
	var label: Label = add_child_autofree(Label.new())
	assert_null(LFHelpTip.attach_tip(label, null))
	assert_push_error('LFHelpTip')
	assert_eq(label.get_child_count(), 0)


func test_a_button_inside_a_tipped_panel_keeps_its_hover():
	var button := Button.new()
	button.text = 'inside'
	var tip := _tipped_panel(button)
	var panel := tip.get_parent() as Panel
	await wait_process_frames(2)

	await _hover(button.get_global_rect().get_center())
	assert_eq(get_viewport().gui_get_hovered_control(), button)
	await _hover(panel.get_global_rect().end - Vector2(10, 10))
	assert_eq(get_viewport().gui_get_hovered_control(), panel)
	assert_not_null(await _shown(tip))


func test_the_wheel_over_a_tipped_container_still_scrolls_its_scroll_container():
	var scroll: ScrollContainer = add_child_autofree(ScrollContainer.new())
	scroll.position = HOVER_AREA
	scroll.size = Vector2(300, 120)
	var column := VBoxContainer.new()
	scroll.add_child(column)
	var row := _tipped_row(column)
	for i in 20:
		var label := Label.new()
		label.text = 'filler %d' % i
		column.add_child(label)
	await wait_process_frames(2)

	var at: Vector2 = row.get_child(0).get_global_rect().get_center()
	await _hover(at)
	assert_eq(get_viewport().gui_get_hovered_control(), row)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.factor = 1.0
		event.position = at
		event.global_position = at
		get_viewport().push_input(event, true)
		await wait_process_frames(1)

	assert_gt(scroll.scroll_vertical, 0, 'the wheel reached the ScrollContainer')


func test_a_tip_moved_to_another_target_leaves_the_first_one():
	var first: Label = add_child_autofree(Label.new())
	var second: Label = add_child_autofree(Label.new())
	var tip := LFHelpTip.attach(first, 'Moves.')

	assert_eq(LFHelpTip.attach_tip(second, tip), tip)

	assert_null(LFHelpTip.of(first), 'taken off the first target')
	assert_eq(tip.get_parent(), second)
	assert_eq(LFHelpTip.of(second), tip)
	assert_false(first.mouse_entered.is_connected(tip._on_target_mouse_entered), 'no longer listening to the first')
	assert_true(second.mouse_entered.is_connected(tip._on_target_mouse_entered))


func test_re_attaching_a_tip_to_its_own_target_keeps_it_and_resets_its_transform():
	var label: Label = add_child_autofree(Label.new())
	var tip := LFHelpTip.attach(label, 'Same.')
	tip.rotation = 1.0
	tip.scale = Vector2(2, 2)

	assert_eq(LFHelpTip.attach_tip(label, tip, 'New hover'), tip)

	assert_eq(label.get_children().filter(func(c): return c is LFHelpTip), [tip], 'not added twice, not freed')
	assert_false(tip.is_queued_for_deletion())
	assert_eq(tip.rotation, 0.0)
	assert_eq(tip.scale, Vector2.ONE)
	assert_eq(tip.tooltip_text, 'New hover')
	assert_eq(tip.name, &"HelpTip")


func test_a_tip_queued_for_deletion_is_not_reported_by_of():
	var label: Label = add_child_autofree(Label.new())
	var tip := LFHelpTip.attach(label, 'Going.')

	tip.queue_free()

	assert_null(LFHelpTip.of(label))


func test_hover_text_of_content_without_a_title():
	assert_eq(LFHelpTip.hover_text_of({'text': 'no title key'}), '')
	assert_eq(LFHelpTip.hover_text_of({'title': ''}), '')
	assert_eq(LFHelpTip.hover_text_of(RefCounted.new()), '', 'an object without a title property')
	var gone := Node.new()
	gone.free()
	assert_eq(LFHelpTip.hover_text_of(gone), '', 'a freed object')


func test_a_tips_own_builder_wins_over_the_default_builder():
	var label: Label = add_child_autofree(Label.new())
	LFHelpTip.default_builder = func(_c): return LFBuild.label(null, 'default')
	var tip := LFHelpTip.attach(label, 'x', func(_c): return LFBuild.label(null, 'own'))

	var panel: Label = autofree(tip.build_panel())

	assert_eq(panel.text, 'own')


func test_a_tip_without_a_control_parent_has_an_empty_help_rect():
	var tip: LFHelpTip = autofree(LFHelpTip.new())
	tip.content = 'x'

	assert_eq(tip.get_help_rect(), Rect2())


func test_a_child_with_its_own_tooltip_shows_that_instead_of_the_help():
	var label := Label.new()
	label.text = 'own'
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = 'Its own tooltip.'
	var tip := _tipped_panel(label)
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())

	assert_eq(get_viewport().gui_get_hovered_control(), label)
	assert_false(await _shows_after_the_delay(tip))


func test_moving_onto_a_child_with_its_own_tooltip_hides_the_help():
	var label := Label.new()
	label.text = 'own'
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = 'Its own tooltip.'
	var tip := _tipped_panel(label)
	var panel := tip.get_parent() as Panel
	await wait_process_frames(2)
	await _hover(panel.get_global_rect().end - Vector2(10, 10))
	await _shown(tip)

	await _hover(label.get_global_rect().get_center())

	assert_null(tip.get_popup())


func test_a_child_ignoring_the_mouse_does_not_take_it_even_with_a_tooltip():
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.tooltip_text = 'Never shown.'
	var tip := _tipped_panel(label)
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())

	assert_eq(get_viewport().gui_get_hovered_control(), tip.get_parent())
	assert_not_null(await _shown(tip))


func test_a_hidden_child_button_does_not_block_the_help():
	var button := Button.new()
	var tip := _tipped_panel(button)
	await wait_process_frames(2)
	var at := button.get_global_rect().get_center()
	button.visible = false
	await wait_process_frames(1)

	await _hover(at)

	assert_not_null(await _shown(tip))


func test_a_button_nested_inside_a_child_keeps_its_hover():
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var button := Button.new()
	button.position = Vector2(10, 5)
	button.size = Vector2(40, 20)
	holder.add_child(button)
	var tip := _tipped_panel(holder)
	await wait_process_frames(2)

	await _hover(button.get_global_rect().get_center())
	assert_eq(get_viewport().gui_get_hovered_control(), button, 'a grandchild that stops the mouse')
	await _hover(holder.get_global_rect().position + Vector2(2, 2))
	assert_eq(get_viewport().gui_get_hovered_control(), holder)
	assert_not_null(await _shown(tip), 'the PASS holder without a tooltip passes the hover on to the target')


## A button sticking out of a clipping child is not drawn there, so the help shows there.
func test_the_part_of_a_button_clipped_away_by_a_child_shows_the_help():
	var clip := Control.new()
	clip.clip_contents = true
	var button := Button.new()
	button.position = Vector2(40, 0)
	button.size = Vector2(120, 30)
	clip.add_child(button)
	var tip := _tipped_panel(clip)
	await wait_process_frames(2)
	var y := clip.get_global_rect().get_center().y

	await _hover(Vector2(clip.get_global_rect().position.x + 60.0, y))
	assert_eq(get_viewport().gui_get_hovered_control(), button, 'inside the clip the button keeps its hover')
	await _hover(Vector2(clip.get_global_rect().end.x + 20.0, y))
	assert_eq(get_viewport().gui_get_hovered_control(), tip.get_parent())
	assert_not_null(await _shown(tip), 'outside the clip the help shows')


func test_a_top_level_child_is_not_part_of_the_target():
	var label := Label.new()
	label.text = 'floating'
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.top_level = true
	var tip := _tipped_panel(label)
	await wait_process_frames(2)

	# Top level, the label is placed at (20, 20) on the canvas, outside the panel.
	await _hover(label.get_global_rect().get_center())

	assert_eq(get_viewport().gui_get_hovered_control(), label)
	assert_false(await _shows_after_the_delay(tip))


func test_hiding_the_target_hides_its_help():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	await _hover(row.get_child(0).get_global_rect().get_center())
	await _shown(tip)

	row.visible = false
	await wait_process_frames(1)

	assert_null(tip.get_popup())


## The game hides a tip to switch its help off (an empty slot has nothing to explain).
func test_a_hidden_tip_shows_nothing_and_hiding_it_closes_its_help():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	var at: Vector2 = row.get_child(0).get_global_rect().get_center()
	await _hover(at)
	await _shown(tip)

	tip.visible = false
	assert_null(tip.get_popup(), 'closed at once')
	await _hover(at + Vector2(2, 0))
	assert_false(await _shows_after_the_delay(tip), 'and not shown again while hidden')


func test_a_freed_target_takes_its_tip_and_window_with_it():
	var row := _tipped_row()
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	await _hover(row.get_child(0).get_global_rect().get_center())
	var popup := await _shown(tip)

	row.free()
	await wait_process_frames(1)

	assert_false(is_instance_valid(tip))
	assert_false(is_instance_valid(popup))


func test_the_tooltip_flips_to_the_other_side_of_the_mouse_at_the_screen_edge():
	var screen := Rect2(0, 0, 1152, 648)
	var size := Vector2(200, 80)

	assert_eq(LFHelpTip._tooltip_rect(Vector2(100, 100), size, screen), Rect2(Vector2(110, 110), size))
	assert_eq(LFHelpTip._tooltip_rect(Vector2(1100, 600), size, screen), Rect2(Vector2(890, 510), size), 'left of and above the mouse')
	assert_eq(LFHelpTip._tooltip_rect(Vector2(100, 40), Vector2(100, 640), screen), Rect2(Vector2(110, 8), Vector2(100, 640)), 'too tall either way: pushed back onto the screen')


func test_a_tooltip_near_the_screen_edge_stays_on_screen():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'corner'
	label.position = Vector2(SCREEN) - Vector2(60, 30)
	var tip := LFHelpTip.attach(label, 'A long help text for the label in the corner.')
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())
	var popup := await _shown(tip)

	assert_true(Rect2(Vector2.ZERO, Vector2(SCREEN)).encloses(Rect2(popup.position, popup.size)))


## A card the way a HUD builds one: a PanelContainer (it stops the mouse) holding a row of
## a label and a button, with a hover highlight driven by its own signals. Tipped as a whole.
func _tipped_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.position = HOVER_AREA
	card.custom_minimum_size = Vector2(300, 100)
	var row := HBoxContainer.new()
	card.add_child(row)
	var label := Label.new()
	label.text = 'card text'
	row.add_child(label)
	var button := Button.new()
	button.text = 'Use'
	row.add_child(button)
	add_child_autofree(card)
	LFHelpTip.attach(card, 'About the card.')
	return card


## A Panel added after the row, overlapping its right end, with a Button inside: drawn over
## the tipped row, so it must keep the mouse there. Both sit in one HUD Control.
func test_a_control_drawn_over_a_tipped_container_keeps_its_hover():
	var hud: Control = add_child_autofree(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _tipped_row(hud)
	var cover := Panel.new()
	hud.add_child(cover)
	await wait_process_frames(2)
	var last: Control = row.get_child(2)
	cover.position = last.get_global_rect().position - Vector2(10, 10)
	cover.size = Vector2(120, 60)
	var button := Button.new()
	button.position = Vector2(5, 5)
	button.size = Vector2(60, 30)
	cover.add_child(button)
	await wait_process_frames(1)

	await _hover(button.get_global_rect().get_center())
	assert_eq(get_viewport().gui_get_hovered_control(), button, 'the button drawn over the row')
	await _hover(cover.get_global_rect().end - Vector2(5, 5))
	assert_eq(get_viewport().gui_get_hovered_control(), cover, 'the panel drawn over the row')


func test_a_tipped_card_still_gets_its_own_mouse_entered_and_motion():
	var card := _tipped_card()
	var entered := []
	var exited := []
	var motions := []
	card.mouse_entered.connect(func(): entered.append(true))
	card.mouse_exited.connect(func(): exited.append(true))
	card.gui_input.connect(func(event: InputEvent): if event is InputEventMouseMotion: motions.append(true))
	await wait_process_frames(2)
	var label: Label = card.get_child(0).get_child(0)

	await _hover(label.get_global_rect().get_center())
	await _hover(label.get_global_rect().get_center() + Vector2(2, 0))
	await _hover(card.get_global_rect().end + Vector2(20, 20))

	assert_eq(entered.size(), 1, 'its hover highlight turns on')
	assert_eq(motions.size(), 2, 'it sees every motion over it')
	assert_eq(exited.size(), 1, 'and off again')


func test_a_button_inside_a_tipped_card_keeps_its_hover_and_click():
	var card := _tipped_card()
	var button: Button = card.get_child(0).get_child(1)
	var presses := []
	button.pressed.connect(func(): presses.append(true))
	await wait_process_frames(2)
	var at := button.get_global_rect().get_center()

	await _hover(at)
	assert_eq(get_viewport().gui_get_hovered_control(), button)
	await _click(at)
	assert_eq(presses.size(), 1)


## A tipped row scrolled half out of its ScrollContainer: the part scrolled away is not
## the row's to hover, and what scrolled into view is.
func test_the_part_of_a_tipped_row_a_scroll_container_clips_is_not_hovered():
	var scroll: ScrollContainer = add_child_autofree(ScrollContainer.new())
	scroll.position = HOVER_AREA
	scroll.size = Vector2(300, 60)
	var column := VBoxContainer.new()
	scroll.add_child(column)
	for i in 2:
		var filler := Label.new()
		filler.text = 'filler %d' % i
		column.add_child(filler)
	var row := _tipped_row(column)
	for i in 10:
		var filler := Label.new()
		filler.text = 'more %d' % i
		column.add_child(filler)
	var below: Button = add_child_autofree(Button.new())
	below.position = HOVER_AREA + Vector2(0, 60)
	below.size = Vector2(300, 60)
	await wait_process_frames(2)
	var entered := []
	row.mouse_entered.connect(func(): entered.append(true))
	var label_x: float = row.get_child(0).get_global_rect().get_center().x
	var row_top: float = row.get_global_rect().position.y
	assert_lt(row_top, scroll.get_global_rect().end.y - 5.0, 'the row starts in view')
	assert_gt(row.get_global_rect().end.y, scroll.get_global_rect().end.y, 'and runs out of it')

	await _hover(Vector2(label_x, scroll.get_global_rect().end.y + 5.0))
	assert_eq(get_viewport().gui_get_hovered_control(), below, 'below the clip the row is not drawn')
	assert_eq(entered.size(), 0)
	await _hover(Vector2(label_x, row_top + 3.0))
	assert_eq(entered.size(), 1, 'inside the clip it is')


func test_hovering_a_tipped_row_while_the_tree_is_paused_shows_its_help():
	var hud: Control = add_child_autofree(Control.new())
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	var row := _tipped_row(hud)
	await wait_process_frames(2)
	var tip := LFHelpTip.of(row)
	# The test's own waits must keep running while the rest of the tree is paused
	# (after_each puts both back).
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	await _hover(row.get_child(0).get_global_rect().get_center())

	assert_false(row.can_process(), 'the HUD row is paused')
	assert_not_null(await _shown(tip))


## How long to wait for Godot's own tooltip, in seconds: twice its default 0.5 s delay
## (Godot's viewport reads the delay setting once, at startup, so DELAY_SEC does not apply).
const GODOT_TOOLTIP_WAIT_SEC := 1.0


## Every tooltip window open in the tree: Godot's own and the tips'.
func _open_tooltip_windows() -> Array[Window]:
	var found: Array[Window] = []
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children(true):
			if child is PopupPanel and child.visible and not child.is_queued_for_deletion():
				found.append(child)
			pending.append(child)
	return found


## A tile Button with a description tooltip holds a tipped Label set to PASS: over the
## label only its help opens, not the tile's plain tooltip as well.
func test_a_parents_plain_tooltip_does_not_open_over_the_help_of_a_passing_target():
	var tile: Button = add_child_autofree(Button.new())
	tile.position = HOVER_AREA
	tile.size = Vector2(200, 100)
	tile.tooltip_text = 'The tile description.'
	var level := Label.new()
	level.text = 'Level 2'
	level.mouse_filter = Control.MOUSE_FILTER_PASS
	level.position = Vector2(10, 10)
	tile.add_child(level)
	var tip := LFHelpTip.attach(level, 'What a level is.')
	await wait_process_frames(2)

	await _hover(level.get_global_rect().get_center())
	await _shown(tip)
	await wait_seconds(GODOT_TOOLTIP_WAIT_SEC)

	assert_eq(_open_tooltip_windows(), [tip.get_popup()] as Array[Window])
	assert_eq(level.tooltip_text, ' ', 'a blank tooltip stops Godot looking further up')


func test_a_tip_inside_a_tipped_target_shows_only_its_own_help():
	var label := Label.new()
	label.text = 'inner'
	var outer := _tipped_panel(label)
	var inner := LFHelpTip.attach(label, 'About the label.')
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())

	assert_not_null(await _shown(inner))
	assert_false(await _shows_after_the_delay(outer))
	await _hover(outer.get_parent().get_global_rect().end - Vector2(10, 10))
	assert_not_null(await _shown(outer), 'the rest of the panel shows the outer help')


## A HUD Control that ignores the mouse, holding a Button at HOVER_AREA (200 x 50) that
## counts its presses into `presses`.
func _hud_with_button(presses: Array) -> Control:
	var hud: Control = add_child_autofree(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.size = Vector2(SCREEN)
	var button := Button.new()
	button.position = HOVER_AREA
	button.size = Vector2(200, 50)
	button.pressed.connect(func(): presses.append(true))
	hud.add_child(button)
	return hud


## A decorative Label laid over a Button as its sibling (the label ignores the mouse, as
## Labels do): the label's help shows over it, and the button under it still gets the click.
func test_a_label_laid_over_a_button_shows_its_help_and_the_button_still_clicks():
	var presses := []
	var hud := _hud_with_button(presses)
	var button: Button = hud.get_child(0)
	var label := Label.new()
	label.text = 'decoration'
	label.position = HOVER_AREA
	label.size = Vector2(200, 50)
	hud.add_child(label)
	var tip := LFHelpTip.attach(label, 'About the decoration.')
	await wait_process_frames(2)
	var at := label.get_global_rect().get_center()

	await _hover(at)
	assert_eq(get_viewport().gui_get_hovered_control(), button, 'the button keeps its hover')
	assert_not_null(await _shown(tip), 'the label drawn on top shows its help')
	await _click(at)

	assert_eq(presses.size(), 1, 'the click reaches the button under the label')
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE)


## The label-inside-a-button case: an ignoring Label child of a Button shows its help, and
## the button takes the click and keeps its hover.
func test_an_ignoring_label_inside_a_button_shows_its_help_and_the_button_takes_the_click():
	var presses := []
	var hud := _hud_with_button(presses)
	var button: Button = hud.get_child(0)
	var label := Label.new()
	label.text = 'Level 2'
	label.position = Vector2(10, 10)
	label.size = Vector2(80, 30)
	button.add_child(label)
	var tip := LFHelpTip.attach(label, 'What a level is.')
	await wait_process_frames(2)
	var at := label.get_global_rect().get_center()

	await _hover(at)
	assert_not_null(await _shown(tip))
	assert_eq(get_viewport().gui_get_hovered_control(), button)
	await _click(at)

	assert_eq(presses.size(), 1)
	await _hover(button.get_global_rect().end - Vector2(5, 5))
	assert_null(tip.get_popup(), 'the rest of the button is not the label')


## An ignoring target with a Button drawn over it (added after it): the button keeps its
## hover and no help shows there.
func test_a_button_drawn_over_an_ignoring_target_covers_its_help():
	var hud: Control = add_child_autofree(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = 'under a button'
	label.position = HOVER_AREA
	label.size = Vector2(200, 50)
	hud.add_child(label)
	var tip := LFHelpTip.attach(label, 'Covered.')
	var cover := Button.new()
	cover.position = HOVER_AREA
	cover.size = Vector2(100, 50)
	hud.add_child(cover)
	await wait_process_frames(2)

	await _hover(cover.get_global_rect().get_center())
	assert_eq(get_viewport().gui_get_hovered_control(), cover)
	assert_false(await _shows_after_the_delay(tip))
	await _hover(label.get_global_rect().end - Vector2(20, 10))
	assert_not_null(await _shown(tip), 'the uncovered part shows the help')


func test_the_part_of_an_ignoring_label_a_clipping_parent_cuts_off_shows_no_help():
	var clip: Control = add_child_autofree(Control.new())
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = HOVER_AREA
	clip.size = Vector2(100, 40)
	var label := Label.new()
	label.text = 'a label wider than its clip'
	label.size = Vector2(300, 40)
	clip.add_child(label)
	var tip := LFHelpTip.attach(label, 'Clipped.')
	await wait_process_frames(2)

	await _hover(HOVER_AREA + Vector2(200, 20))
	assert_false(await _shows_after_the_delay(tip), 'cut off: not drawn there')
	await _hover(HOVER_AREA + Vector2(50, 20))
	assert_not_null(await _shown(tip))


func test_an_ignoring_tip_inside_an_ignoring_tipped_target_shows_only_its_own_help():
	var box: VBoxContainer = add_child_autofree(VBoxContainer.new())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = HOVER_AREA
	box.custom_minimum_size = Vector2(200, 100)
	var label := Label.new()
	label.text = 'inner'
	box.add_child(label)
	var outer := LFHelpTip.attach(box, 'About the box.')
	var inner := LFHelpTip.attach(label, 'About the label.')
	await wait_process_frames(2)

	await _hover(label.get_global_rect().get_center())
	assert_not_null(await _shown(inner))
	assert_false(await _shows_after_the_delay(outer))
	await _hover(box.get_global_rect().end - Vector2(10, 10))
	assert_not_null(await _shown(outer), 'the rest of the box shows the outer help')
	assert_null(inner.get_popup())


func test_hovering_an_ignoring_label_while_the_tree_is_paused_shows_its_help():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'paused'
	label.position = HOVER_AREA
	label.process_mode = Node.PROCESS_MODE_PAUSABLE
	var tip := LFHelpTip.attach(label, 'Still explained.')
	await wait_process_frames(2)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	await _hover(label.get_global_rect().get_center())

	assert_not_null(await _shown(tip))


## A help window too big to fit beside the mouse opens under it: Godot then counts the
## mouse over the window, not the target. Moving the mouse a little must not close and
## reopen it over and over (for a target that takes the mouse and for one that does not).
func test_a_help_window_opened_under_the_mouse_stays_open_while_the_mouse_moves():
	var huge := func(_c: Variant) -> Control:
		var panel := Control.new()
		panel.custom_minimum_size = Vector2(1100, 600)
		return panel
	for filter in [Control.MOUSE_FILTER_STOP, Control.MOUSE_FILTER_IGNORE]:
		var target: Control = add_child_autofree(Panel.new())
		target.mouse_filter = filter
		target.position = Vector2(500, 300)
		target.size = Vector2(200, 60)
		var tip := LFHelpTip.attach(target, 'big', huge)
		await wait_process_frames(2)
		var at := target.get_global_rect().get_center()
		await _hover(at)
		var first := await _shown(tip)
		assert_not_null(first)
		assert_true(Rect2(first.position, first.size).has_point(at), 'the window opened under the mouse')

		var windows := [first]
		for i in 10:
			await _hover(at + Vector2(i % 2, 0))
			await wait_seconds(DELAY_SEC * 2.0)
			if tip.get_popup() != null and not windows.has(tip.get_popup()):
				windows.append(tip.get_popup())
			if tip.get_popup() == null:
				windows.append(null)

		assert_eq(windows, [first], 'one window, open all along (filter %d)' % filter)
		await _hover(Vector2(5, 5))
		await wait_process_frames(1)
		assert_null(tip.get_popup(), 'leaving the window and the target closes it')
		target.free()


## Moving onto a help window that opened beside the mouse is leaving the target, as with
## Godot's own tooltip.
func test_moving_onto_a_help_window_beside_the_mouse_closes_it():
	var panel: Panel = add_child_autofree(Panel.new())
	panel.position = HOVER_AREA
	panel.size = Vector2(400, 200)
	var tip := LFHelpTip.attach(panel, 'Short help.')
	await wait_process_frames(2)
	await _hover(HOVER_AREA + Vector2(20, 20))
	var popup := await _shown(tip)

	await _hover(Rect2(popup.position, popup.size).get_center())
	await wait_process_frames(1)

	assert_null(tip.get_popup())


func test_a_help_window_hidden_by_something_else_comes_back_on_the_next_motion():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'Gold: 120'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, 'Spent at the merchant.')
	await wait_process_frames(2)
	var at := label.get_global_rect().get_center()
	await _hover(at)
	var first := await _shown(tip)

	first.hide()
	assert_null(tip.get_popup(), 'the hidden window is let go')
	await _hover(at + Vector2(2, 0))

	var again := await _shown(tip)
	assert_not_null(again)
	assert_ne(again, first)
	assert_true(again.visible)


## Where Godot's own tooltip for `owner` opens with the mouse at `at`, then where the help
## of a tip on `owner` opens for the same motion; both in the embedding viewport's pixels.
func _godot_and_help_positions(owner: Control, at: Vector2) -> Array[Vector2i]:
	owner.mouse_filter = Control.MOUSE_FILTER_PASS
	owner.tooltip_text = 'Plain text.'
	await wait_process_frames(2)
	await _hover(at)
	await wait_seconds(GODOT_TOOLTIP_WAIT_SEC)
	var godot := _open_tooltip_windows()
	var godot_at := godot[0].position if godot.size() == 1 else Vector2i(-1, -1)
	await _hover(Vector2(1, 1))
	await wait_process_frames(2)
	owner.tooltip_text = ''
	var tip := LFHelpTip.attach(owner, 'Plain text.', func(_c: Variant) -> Control: return null)
	await wait_process_frames(2)
	await _hover(at)
	var popup := await _shown(tip)
	return [godot_at, popup.position if popup != null else Vector2i(-2, -2)]


func test_the_help_inside_a_sub_viewport_opens_where_godots_tooltip_does():
	var container: SubViewportContainer = add_child_autofree(SubViewportContainer.new())
	container.position = Vector2(300, 200)
	container.size = Vector2(400, 300)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	container.add_child(viewport)
	var label := Label.new()
	label.text = 'in a sub viewport'
	label.position = Vector2(10, 10)
	label.size = Vector2(150, 30)
	viewport.add_child(label)

	var positions := await _godot_and_help_positions(label, Vector2(321, 221))

	assert_eq(positions[1], positions[0])
	assert_eq(positions[1], Vector2i(331, 231), 'the mouse plus the offset, in the main viewport')


func test_the_help_inside_an_embedded_window_opens_where_godots_tooltip_does():
	# Not autofreed: freeing an embedded Window outright, right after the mouse left it,
	# leaves Godot a queued call on the freed window.
	var window := Window.new()
	add_child(window)
	window.position = Vector2i(500, 300)
	window.size = Vector2i(300, 200)
	var label := Label.new()
	label.text = 'in a window'
	label.position = Vector2(10, 10)
	label.size = Vector2(150, 30)
	window.add_child(label)

	var positions := await _godot_and_help_positions(label, Vector2(521, 321))
	await _hover(Vector2(1, 1))
	window.queue_free()
	await wait_process_frames(2)

	assert_eq(positions[1], positions[0])
	assert_eq(positions[1], Vector2i(531, 331))


## The help tour shows one target's help on its card; a hover help next to it would be a
## second, different one.
func test_opening_the_help_tour_closes_hover_help_and_keeps_it_closed():
	var browser: LFHelpBrowser = add_child_autofree(LFHelpBrowser.new())
	var label: Label = add_child_autofree(Label.new())
	label.text = 'Gold: 120'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, 'Spent at the merchant.')
	await wait_process_frames(2)
	var at := label.get_global_rect().get_center()
	await _hover(at)
	await _shown(tip)

	browser.open()
	assert_true(browser.is_open())
	assert_null(tip.get_popup(), 'closed when the tour opens')
	await _hover(at + Vector2(2, 0))
	assert_false(await _shows_after_the_delay(tip), 'and not shown while it is open')

	browser.close()
	await _hover(at + Vector2(4, 0))
	assert_not_null(await _shown(tip), 'back once the tour closes')


func test_a_default_builder_is_cleared_when_the_tree_starts_to_quit():
	LFHelpTip.default_builder = func(_c): return LFBuild.label(null, 'x')
	var ours: Array[Callable] = []
	for connection in get_tree().root.tree_exiting.get_connections():
		var hook: Callable = connection['callable']
		if hook.get_object() == LFHelpTip:
			ours.append(hook)
	assert_eq(ours.size(), 1, 'one quit hook, however often the builder is set')
	LFHelpTip.default_builder = func(_c): return LFBuild.label(null, 'y')

	ours[0].call()

	assert_false(LFHelpTip.default_builder.is_valid())


func test_blank_text_content_builds_no_panel_and_shows_no_empty_window():
	var label: Label = add_child_autofree(Label.new())
	label.text = 'x'
	label.position = HOVER_AREA
	var tip := LFHelpTip.attach(label, '  ')
	await wait_process_frames(2)

	assert_null(tip.build_panel())
	await _hover(label.get_global_rect().get_center())
	assert_false(await _shows_after_the_delay(tip))
