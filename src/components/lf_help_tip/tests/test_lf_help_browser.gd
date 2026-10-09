extends GutTest

## Holding F1 or the pad's Back button steps through every help tip on screen in reading
## order; `toggle()` does the same for an on-screen button.

class SubTip:
	extends LFHelpTip


var browser: LFHelpBrowser
var root: Control


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


func before_each():
	_pin_screen()
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(root)
	browser = LFHelpBrowser.new()
	add_child_autofree(browser)


func after_each():
	# Replaced panels and tips are queue_free()d out of the tree; let them go.
	await wait_process_frames(1)
	_unpin_screen()


static func _panel(content: Dictionary) -> Control:
	var box := VBoxContainer.new()
	LFBuild.label(box, content.title)
	LFBuild.label(box, content.explanation)
	LFBuild.label(box, content.example)
	return box


func _label_with_help(parent: Control, title: String, at: Vector2) -> Label:
	var label := Label.new()
	label.text = title
	label.position = at
	label.size = Vector2(80, 20)
	parent.add_child(label)
	LFHelpTip.attach(label, {'title': title, 'explanation': 'about ' + title, 'example': 'e.g. ' + title}, _panel)
	return label


func _titles(tips: Array) -> Array:
	return tips.map(func(t): return t.content.title)


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _shown_title() -> String:
	return browser.current.content.title if browser.current != null else ''


func test_targets_are_every_visible_help_in_reading_order():
	_label_with_help(root, 'C', Vector2(20, 200))
	_label_with_help(root, 'B', Vector2(300, 22))
	_label_with_help(root, 'A', Vector2(20, 20))
	var hidden := _label_with_help(root, 'Hidden', Vector2(20, 100))
	hidden.visible = false
	_label_with_help(root, 'Off', Vector2(-500, -500))
	await wait_process_frames(1)

	assert_eq(_titles(browser.visible_targets()), ['A', 'B', 'C'], 'rows top to bottom, left to right within a row; hidden and off-screen ones skipped')


func test_holding_f1_opens_on_the_first_and_releasing_closes():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	watch_signals(browser)

	browser.input_layers.route(_key(KEY_F1, true))
	assert_true(browser.is_open())
	assert_true(browser.is_held_open())
	assert_eq(_shown_title(), 'A')
	assert_true(browser.card.visible)
	assert_true(browser.frame.visible)
	assert_string_contains(browser.counter_label.text, 'release to close')
	assert_signal_emitted(browser, 'opened')

	browser.input_layers.route(_key(KEY_F1, false))
	assert_false(browser.is_open())
	assert_false(browser.card.visible)
	assert_signal_emitted(browser, 'closed')


func test_f1_from_the_viewport_opens_before_gui_controls_see_it():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	var seen := []
	var focused := Control.new()
	focused.focus_mode = Control.FOCUS_ALL
	focused.gui_input.connect(func(event: InputEvent): seen.append(event))
	root.add_child(focused)
	focused.grab_focus()

	get_viewport().push_input(_key(KEY_F1, true))

	assert_true(browser.is_open())
	assert_eq(seen, [], 'the key was taken before it reached the focused control')


func test_a_browser_put_back_in_the_tree_still_answers_the_key():
	_label_with_help(root, 'A', Vector2(20, 20))
	remove_child(browser)
	add_child(browser)
	await wait_process_frames(1)

	get_viewport().push_input(_key(KEY_F1, true))

	assert_true(browser.is_open())


func test_the_gamepad_back_button_works_the_same():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_BACK
	press.pressed = true

	browser.input_layers.route(press)
	assert_true(browser.is_open())

	var release := InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_BACK
	release.pressed = false
	browser.input_layers.route(release)
	assert_false(browser.is_open())


func test_the_hold_key_and_button_can_be_changed():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	browser.hold_key = KEY_H

	assert_false(browser.input_layers.route(_key(KEY_F1, true)))
	assert_false(browser.is_open())
	browser.input_layers.route(_key(KEY_H, true))
	assert_true(browser.is_open())


func test_arrows_or_dpad_step_through_and_wrap():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	_label_with_help(root, 'C', Vector2(20, 220))
	await wait_process_frames(1)
	browser.input_layers.route(_key(KEY_F1, true))

	browser.input_layers.route(_action('ui_right'))
	assert_eq(_shown_title(), 'B')
	browser.input_layers.route(_action('ui_down'))
	assert_eq(_shown_title(), 'C')
	browser.input_layers.route(_action('ui_right'))
	assert_eq(_shown_title(), 'A', 'wraps past the last')
	browser.input_layers.route(_action('ui_left'))
	assert_eq(_shown_title(), 'C', 'and back past the first')
	assert_string_contains(browser.counter_label.text, '3 / 3')


func test_arrows_do_nothing_while_closed():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)

	assert_false(browser.input_layers.route(_action('ui_right')))

	assert_false(browser.is_open())
	assert_null(browser.current)


func test_the_toggle_stays_open_through_a_key_release_and_closes_on_a_second_toggle():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)

	browser.toggle()
	browser.input_layers.route(_key(KEY_F1, false))
	assert_true(browser.is_open(), 'opened by the toggle, not by holding the key')
	assert_false(browser.is_held_open())
	assert_string_contains(browser.counter_label.text, 'Help again to close')

	browser.toggle()
	assert_false(browser.is_open())


func test_with_nothing_to_explain_it_does_not_open():
	browser.toggle()

	assert_false(browser.is_open())


func test_the_card_shows_the_targets_help_beside_it():
	var label := _label_with_help(root, 'item_a', Vector2(20, 20))
	await wait_process_frames(1)

	browser.open()

	var content: VBoxContainer = browser.card.get_child(0).get_child(0)
	assert_eq((content.get_child(0) as Label).text, 'item_a')
	assert_eq((content.get_child(2) as Label).text, 'e.g. item_a')
	assert_gt(browser.card.position.x, label.get_global_rect().end.x, 'beside the target, not over it')
	assert_eq(browser.frame.position, label.get_global_rect().grow(browser.frame_pad_px).position)


func test_the_counter_text_and_styles_can_be_set():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	var frame_style := StyleBoxFlat.new()
	var card_style := StyleBoxFlat.new()
	browser.frame_style = frame_style
	browser.card_style = card_style
	browser.counter_text = func(index, total, held): return '%d of %d%s' % [index + 1, total, ' (held)' if held else '']

	browser.open()

	assert_eq(browser.counter_label.text, '1 of 2')
	assert_eq(browser.frame.get_theme_stylebox(&"panel"), frame_style)
	assert_eq(browser.card.get_theme_stylebox(&"panel"), card_style)


func test_a_vanished_target_moves_the_tour_on_and_none_left_closes_it():
	var a := _label_with_help(root, 'A', Vector2(20, 20))
	var b := _label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	browser.open()

	a.visible = false
	await wait_process_frames(2)
	assert_eq(_shown_title(), 'B')

	b.visible = false
	await wait_process_frames(2)
	assert_false(browser.is_open())


func test_a_full_screen_in_the_scope_group_limits_browsing_to_itself():
	_label_with_help(root, 'tip_a', Vector2(20, 20))
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	screen.add_to_group(browser.scope_group)
	_label_with_help(screen, 'tip_b', Vector2(400, 20))
	await wait_process_frames(1)

	assert_eq(_titles(browser.visible_targets()), ['tip_b'])

	screen.visible = false
	assert_eq(_titles(browser.visible_targets()), ['tip_a'], 'the HUD is browsable again once the screen is gone')


## A subclass of LFHelpTip (an app's own tip type) is found too.
func test_tips_of_a_subclass_are_browsed():
	var label := Label.new()
	label.position = Vector2(20, 20)
	label.size = Vector2(80, 20)
	root.add_child(label)
	var tip := SubTip.new()
	tip.content = {'title': 'Sub', 'explanation': '', 'example': ''}
	tip.builder = _panel
	LFHelpTip.attach_tip(label, tip)
	await wait_process_frames(1)

	assert_eq(_titles(browser.visible_targets()), ['Sub'])


func test_step_moves_both_ways_and_closes_when_no_target_is_left():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	browser.open()
	watch_signals(browser)

	browser.step(1)
	assert_eq(_shown_title(), 'B')
	browser.step(-3)
	assert_eq(_shown_title(), 'A')

	root.visible = false
	browser.step(1)
	assert_false(browser.is_open())
	assert_null(browser.current)
	assert_signal_emitted(browser, 'closed')


func test_open_and_close_are_idempotent():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	watch_signals(browser)

	browser.open()
	browser.open()
	browser.close()
	browser.close()

	assert_signal_emit_count(browser, 'opened', 1)
	assert_signal_emit_count(browser, 'closed', 1)


func test_the_default_counter_text():
	assert_eq(browser.format_counter(1, 5, true), '2 / 5   ←/→ next   release to close')
	assert_eq(browser.format_counter(0, 1, false), '1 / 1   ←/→ next   Help again to close')


func test_a_builder_returning_null_shows_the_hover_text():
	var label := Label.new()
	label.position = Vector2(20, 20)
	label.size = Vector2(80, 20)
	root.add_child(label)
	LFHelpTip.attach(label, 'x', func(_content) -> Control: return null, 'Plain words')
	await wait_process_frames(1)

	browser.open()

	assert_eq((browser.card.get_child(0).get_child(0) as Label).text, 'Plain words')


func test_gap_px_sets_the_space_between_the_target_and_its_card():
	var label := _label_with_help(root, 'item_a', Vector2(20, 20))
	await wait_process_frames(1)
	browser.gap_px = 40.0

	browser.open()

	assert_eq(browser.card.position.x, label.get_global_rect().grow(browser.frame_pad_px).end.x + 40.0)


func test_row_tolerance_px_decides_which_targets_share_a_row():
	_label_with_help(root, 'Right', Vector2(300, 20))
	_label_with_help(root, 'Left', Vector2(20, 50))
	await wait_process_frames(1)

	browser.row_tolerance_px = 40.0
	assert_eq(_titles(browser.visible_targets()), ['Left', 'Right'], 'tops 30 px apart are one row: left to right')
	browser.row_tolerance_px = 10.0
	assert_eq(_titles(browser.visible_targets()), ['Right', 'Left'], 'tops 30 px apart are two rows: top to bottom')


func test_step_while_closed_shows_nothing():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)

	browser.step(1)

	assert_false(browser.is_open())
	assert_null(browser.current)
	assert_false(browser.card.visible, 'no card left on screen by a closed tour')
	assert_false(browser.frame.visible)


func test_while_open_the_hold_key_never_passes_through():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	browser.input_layers.route(_key(KEY_F1, true))
	var echo := _key(KEY_F1, true)
	echo.echo = true

	assert_true(browser.input_layers.route(echo), 'a key-repeat of the held key is taken too')
	assert_true(browser.is_open())

	browser.close()
	browser.toggle()
	assert_true(browser.input_layers.route(_key(KEY_F1, false)), 'a release while toggled open is taken')
	assert_true(browser.is_open())
	assert_false(browser.input_layers.route(_key(KEY_K, true)), 'other keys pass')


func test_a_tip_on_a_container_target_is_browsed():
	var row := HBoxContainer.new()
	row.position = Vector2(20, 20)
	root.add_child(row)
	for i in 2:
		var label := Label.new()
		label.text = 'item %d' % i
		row.add_child(label)
	LFHelpTip.attach(row, {'title': 'Row', 'explanation': '', 'example': ''}, _panel)
	await wait_process_frames(2)

	assert_eq(_titles(browser.visible_targets()), ['Row'])
	browser.open()
	assert_eq(browser.frame.position, row.get_global_rect().grow(browser.frame_pad_px).position)


func _stick(axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = axis_value
	return event


## A stick sends a stream of motion events per push; one push moves one tip.
func test_one_stick_push_steps_once():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	_label_with_help(root, 'C', Vector2(20, 220))
	await wait_process_frames(1)
	browser.open()
	assert_true(_stick(0.8).is_action_pressed('ui_right'), 'the project maps the left stick to ui_right')

	for value in [0.6, 0.8, 1.0]:
		assert_true(browser.input_layers.route(_stick(value)))
	assert_eq(_shown_title(), 'B', 'one push, one step')

	browser.input_layers.route(_stick(0.1))
	browser.input_layers.route(_stick(0.9))
	assert_eq(_shown_title(), 'C', 'released below the deadzone, the next push steps again')

	browser.input_layers.route(_stick(0.0))
	browser.input_layers.route(_stick(-0.9))
	browser.input_layers.route(_stick(-1.0))
	assert_eq(_shown_title(), 'B', 'a push the other way steps back once')


func test_a_tip_in_an_offset_canvas_layer_is_framed_where_it_is_drawn():
	var canvas_layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	canvas_layer.offset = Vector2(400, 100)
	var holder := Control.new()
	canvas_layer.add_child(holder)
	var label := _label_with_help(holder, 'Layered', Vector2(20, 20))
	await wait_process_frames(1)

	browser.open()

	assert_eq(browser.frame.position, Rect2(Vector2(420, 120), label.size).grow(browser.frame_pad_px).position)


func test_a_tip_drawn_on_screen_by_its_layer_is_not_culled():
	var canvas_layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	canvas_layer.offset = Vector2(1000, 0)
	var holder := Control.new()
	canvas_layer.add_child(holder)
	_label_with_help(holder, 'Back on screen', Vector2(-900, 20))
	_label_with_help(holder, 'Pushed off screen', Vector2(500, 20))
	await wait_process_frames(1)

	assert_eq(_titles(browser.visible_targets()), ['Back on screen'])


func test_the_tour_works_while_the_tree_is_paused():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	get_tree().paused = true

	get_viewport().push_input(_key(KEY_F1, true))
	var opened := browser.is_open()
	get_tree().paused = false

	assert_eq(browser.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(opened)


func test_a_browser_outside_the_tree_finds_nothing_and_does_not_open():
	_label_with_help(root, 'A', Vector2(20, 20))
	var loose: LFHelpBrowser = autofree(LFHelpBrowser.new())

	assert_eq(loose.visible_targets(), [])
	loose.open()
	assert_false(loose.is_open())


func test_a_target_with_no_area_or_a_queued_tip_is_skipped():
	_label_with_help(root, 'A', Vector2(20, 20))
	var flat := Control.new()
	flat.position = Vector2(20, 100)
	flat.size = Vector2(80, 0)
	root.add_child(flat)
	LFHelpTip.attach(flat, {'title': 'Flat'})
	var going := _label_with_help(root, 'Going', Vector2(20, 200))
	await wait_process_frames(1)

	LFHelpTip.of(going).queue_free()

	assert_eq(_titles(browser.visible_targets()), ['A'])


func test_the_frame_follows_a_target_that_moves_while_open():
	var label := _label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	browser.open()

	label.position = Vector2(300, 200)
	await wait_process_frames(2)

	assert_eq(browser.frame.position, label.get_global_rect().grow(browser.frame_pad_px).position)


func test_a_freed_target_moves_the_tour_on():
	var a := _label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	browser.open()

	a.free()
	await wait_process_frames(2)

	assert_true(browser.is_open())
	assert_eq(_shown_title(), 'B')


func test_stepping_replaces_the_help_panel_instead_of_stacking_it():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	browser.open()
	var box := browser.card.get_child(0)
	var first := box.get_child(0)

	browser.step(1)

	assert_eq(box.get_child_count(), 2, 'the help panel and the counter, nothing left over')
	assert_ne(box.get_child(0), first)
	assert_true(first.is_queued_for_deletion())
	assert_eq(box.get_child(1), browser.counter_label)
	assert_eq(browser.counter_label.text, '2 / 2   ←/→ next   Help again to close')


func test_a_hold_key_matched_by_its_physical_key_opens_the_tour():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F1
	event.pressed = true

	assert_true(browser.input_layers.route(event))

	assert_true(browser.is_held_open())


func test_with_nothing_to_explain_the_hold_key_is_still_taken_but_nothing_opens():
	assert_true(browser.input_layers.route(_key(KEY_F1, true)), 'every press of the hold key is taken')
	assert_false(browser.is_open())
	assert_false(browser.is_held_open())
	assert_false(browser.input_layers.route(_key(KEY_F1, false)), 'a release while closed passes through')


func test_pressing_the_hold_key_while_toggled_open_keeps_the_tour_toggled():
	_label_with_help(root, 'A', Vector2(20, 20))
	await wait_process_frames(1)
	browser.toggle()

	assert_true(browser.input_layers.route(_key(KEY_F1, true)))
	assert_true(browser.input_layers.route(_key(KEY_F1, false)))

	assert_true(browser.is_open(), 'a toggled tour does not close on a release')
	assert_false(browser.is_held_open())


func test_an_arrow_release_while_open_passes_through():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)
	browser.open()
	var release := _action('ui_right')
	release.pressed = false

	assert_false(browser.input_layers.route(release))
	assert_eq(_shown_title(), 'A')


func test_a_stick_while_closed_or_inside_the_deadzone_passes_through():
	_label_with_help(root, 'A', Vector2(20, 20))
	_label_with_help(root, 'B', Vector2(20, 120))
	await wait_process_frames(1)

	assert_false(browser.input_layers.route(_stick(0.9)), 'closed: the stick is not taken')
	browser.open()
	assert_false(browser.input_layers.route(_stick(0.1)), 'inside the deadzone: nothing pushed')
	assert_true(browser.input_layers.route(_stick(0.9)), 'a push made while closed did not stay latched')
	assert_eq(_shown_title(), 'B')


func test_rect_on_layer_measures_a_plain_control_and_maps_through_the_layer():
	var plain := Control.new()
	plain.position = Vector2(100, 50)
	plain.size = Vector2(40, 20)
	root.add_child(plain)
	await wait_process_frames(1)
	browser.offset = Vector2(10, 5)

	assert_eq(browser.rect_on_layer(plain), Rect2(Vector2(90, 45), Vector2(40, 20)))


func test_defaults():
	assert_eq(browser.layer, 90)
	assert_eq(browser.hold_key, KEY_F1)
	assert_eq(browser.hold_button, JOY_BUTTON_BACK)
	assert_eq(browser.scope_group, LFHelpBrowser.DEFAULT_SCOPE_GROUP)
	assert_eq(browser.row_tolerance_px, LFHelpBrowser.DEFAULT_ROW_TOLERANCE_PX)
	assert_eq(browser.gap_px, LFHelpBrowser.DEFAULT_GAP_PX)
	assert_eq(browser.frame_pad_px, LFHelpBrowser.DEFAULT_FRAME_PAD_PX)
	assert_false((browser.frame.get_theme_stylebox(&"panel") as StyleBoxFlat).draw_center, 'the frame is an outline')
	assert_not_null(browser.card.get_theme_stylebox(&"panel"))
	assert_eq(browser.input_layers.stage, LFInputManager.Stage.INPUT)
	assert_null(browser.current)


func test_leaving_the_tree_closes_an_open_tour_so_tips_show_hover_help_again():
	_label_with_help(root, 'Gold', Vector2(40, 40))
	browser.open()
	assert_true(browser.is_open())
	var closed_count := [0]
	browser.closed.connect(func() -> void: closed_count[0] += 1)

	remove_child(browser)

	assert_false(browser.is_open())
	assert_eq(closed_count[0], 1)
	assert_null(get_tree().get_first_node_in_group(LFHelpTip._BROWSING_GROUP))
	add_child(browser)
