extends GutTest


class SkipsSuperInEnterTree extends LFLayoutControl:
	func _enter_tree() -> void:
		pass


func test_entering_the_tree_makes_it_click_through_and_unfocusable():
	var control = add_child_autofree(LFLayoutControl.new())
	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(control.focus_mode, Control.FOCUS_NONE)


func test_a_caller_change_is_reset_to_click_through_on_the_next_tree_entry():
	var control = LFLayoutControl.new()
	add_child_autofree(control)
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.focus_mode = Control.FOCUS_ALL

	remove_child(control)
	add_child(control)

	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(control.focus_mode, Control.FOCUS_NONE)


func test_a_preset_mouse_filter_is_overridden_on_entry():
	var control = LFLayoutControl.new()
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child_autofree(control)
	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_a_subclass_skipping_super_in_enter_tree_is_still_click_through():
	var control = SkipsSuperInEnterTree.new()
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.focus_mode = Control.FOCUS_ALL

	add_child_autofree(control)

	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(control.focus_mode, Control.FOCUS_NONE)


func test_the_packaged_scene_is_a_full_rect_click_through_layout_control():
	var scene: PackedScene = load(get_script().resource_path.get_base_dir().path_join('../lf_layout_control.tscn'))
	var control = add_child_autofree(scene.instantiate())

	assert_true(control is LFLayoutControl)
	assert_eq([control.anchor_right, control.anchor_bottom], [1.0, 1.0])
	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(control.focus_mode, Control.FOCUS_NONE)


func test_a_mouse_click_over_it_reaches_the_button_beneath():
	# A viewport of its own, so nothing other tests left on the root can take the click.
	var viewport: SubViewport = add_child_autofree(SubViewport.new())
	viewport.size = Vector2i(200, 200)
	var below := Button.new()
	below.size = Vector2(100, 100)
	viewport.add_child(below)
	var overlay := LFLayoutControl.new()
	overlay.size = Vector2(100, 100)
	viewport.add_child(overlay)
	watch_signals(below)
	await wait_process_frames(1)

	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = Vector2(50, 50)
		click.global_position = click.position
		viewport.push_input(click, true)
		await wait_process_frames(1)

	assert_signal_emitted(below, 'pressed', 'the overlay let the click through')
