extends GutTest


## Starts `LFPromptDialog.ask` without blocking the test: `result.value` is set when it answers.
func _start(parent: Node, trim_text := true, initial_text := '') -> Dictionary:
	var result := {'done': false, 'value': null}
	var run := func() -> void:
		result.value = await LFPromptDialog.ask(parent, 'Name', 'Type here', 'Save', 'Back', trim_text, initial_text)
		result.done = true
	run.call()
	return result


func _popup(parent: Node) -> LFPromptDialog:
	return parent.get_child(0) as LFPromptDialog


func _type(popup: LFPromptDialog, text: String) -> void:
	popup.edit.text = text
	popup.edit.text_changed.emit(text)


func test_ask_shows_title_placeholder_and_button_labels():
	var parent: Node = add_child_autofree(Node.new())
	_start(parent)
	var popup := _popup(parent)

	assert_eq(popup.title_label.text, 'Name')
	assert_eq(popup.edit.placeholder_text, 'Type here')
	assert_eq(popup.ok_button.text, 'Save')
	assert_eq(popup.cancel_button.text, 'Back')
	popup.cancel()


func test_ok_is_disabled_until_there_is_text():
	var parent: Node = add_child_autofree(Node.new())
	_start(parent)
	var popup := _popup(parent)
	assert_true(popup.ok_button.disabled)

	_type(popup, 'a')
	assert_false(popup.ok_button.disabled)

	_type(popup, '')
	assert_true(popup.ok_button.disabled)
	popup.cancel()


func test_spaces_alone_do_not_enable_ok_when_trimming():
	var parent: Node = add_child_autofree(Node.new())
	_start(parent)
	var popup := _popup(parent)

	_type(popup, '   ')

	assert_true(popup.ok_button.disabled)
	popup.cancel()


func test_spaces_alone_count_without_trim():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent, false)
	var popup := _popup(parent)

	_type(popup, '  ')
	assert_false(popup.ok_button.disabled)
	popup.ok_button.pressed.emit()

	assert_eq(result.value, '  ')


func test_ok_returns_the_trimmed_text_and_frees_the_popup():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	_type(popup, '  Ana ')
	popup.ok_button.pressed.emit()

	assert_true(result.done)
	assert_eq(result.value, 'Ana')
	await wait_process_frames(2)
	assert_eq(parent.get_child_count(), 0)


func test_enter_submits():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	_type(popup, 'Ana')
	popup.edit.text_submitted.emit('Ana')

	assert_eq(result.value, 'Ana')


func test_enter_on_an_empty_field_does_nothing():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	popup.edit.text_submitted.emit('')

	assert_false(result.done)
	popup.cancel()


func test_cancel_returns_an_empty_string():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	_type(popup, 'Ana')
	popup.cancel_button.pressed.emit()

	assert_true(result.done)
	assert_eq(result.value, '')


func test_escape_cancels():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true

	_popup(parent)._input(event)

	assert_eq(result.value, '')


func test_initial_text_fills_the_field_and_enables_ok():
	var parent: Node = add_child_autofree(Node.new())
	_start(parent, true, 'Old name')
	var popup := _popup(parent)

	assert_eq(popup.edit.text, 'Old name')
	assert_false(popup.ok_button.disabled)
	popup.cancel()


func test_a_freed_parent_returns_an_empty_string():
	var holder: Node = add_child_autofree(Node.new())
	var parent := Node.new()
	holder.add_child(parent)
	var result := _start(parent)

	parent.free()

	assert_true(result.done)
	assert_eq(result.value, '')


func test_a_parent_outside_the_tree_returns_an_empty_string_with_an_error():
	var parent := Node.new()
	var result := _start(parent)

	assert_eq(result.value, '')
	assert_push_error('scene tree')
	parent.free()
