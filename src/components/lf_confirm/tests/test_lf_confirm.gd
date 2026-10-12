extends GutTest

const TITLE := 'Quit?'
const TEXT := 'Progress is lost.'


## Starts `LFConfirm.ask` without blocking the test: `result.value` is set when it answers.
func _start(parent: Node, focus_yes := false) -> Dictionary:
	var result := {'done': false, 'value': null}
	var run := func() -> void:
		result.value = await LFConfirm.ask(parent, TITLE, TEXT, 'Yes', 'No', focus_yes)
		result.done = true
	run.call()
	return result


func _popup(parent: Node) -> LFConfirm:
	return parent.get_child(0) as LFConfirm


func test_ask_shows_title_text_and_button_labels():
	var parent: Node = add_child_autofree(Node.new())
	var run := func() -> void:
		await LFConfirm.ask(parent, TITLE, TEXT, 'Leave', 'Stay')
	run.call()
	var popup := _popup(parent)

	assert_eq(popup.title_label.text, TITLE)
	assert_eq(popup.text_label.text, TEXT)
	assert_eq(popup.yes_button.text, 'Leave')
	assert_eq(popup.no_button.text, 'Stay')
	popup.answer(false)


func test_yes_returns_true_and_frees_the_popup():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	popup.yes_button.pressed.emit()

	assert_true(result.done)
	assert_true(result.value)
	await wait_process_frames(2)
	assert_eq(parent.get_child_count(), 0, 'the popup freed itself')


func test_no_returns_false():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)

	_popup(parent).no_button.pressed.emit()

	assert_true(result.done)
	assert_false(result.value)


func test_no_has_the_focus_by_default():
	var parent: Node = add_child_autofree(Control.new())
	_start(parent)
	var popup := _popup(parent)

	assert_true(popup.no_button.has_focus())
	popup.answer(false)


func test_focus_yes_moves_the_focus():
	var parent: Node = add_child_autofree(Control.new())
	_start(parent, true)
	var popup := _popup(parent)

	assert_true(popup.yes_button.has_focus())
	popup.answer(false)


func test_escape_returns_false():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true

	_popup(parent)._input(event)

	assert_true(result.done)
	assert_false(result.value)


func test_a_freed_parent_returns_false():
	var holder: Node = add_child_autofree(Node.new())
	var parent := Node.new()
	holder.add_child(parent)
	var result := _start(parent)

	parent.free()

	assert_true(result.done)
	assert_false(result.value)


func test_the_first_answer_wins():
	var parent: Node = add_child_autofree(Node.new())
	var result := _start(parent)
	var popup := _popup(parent)

	popup.answer(true)
	popup.answer(false)

	assert_true(result.value)


func test_a_parent_outside_the_tree_returns_false_with_an_error():
	var parent := Node.new()
	var result := _start(parent)

	assert_true(result.done)
	assert_false(result.value)
	assert_push_error('scene tree')
	parent.free()


func test_a_null_parent_returns_false_with_an_error():
	var result := _start(null)

	assert_false(result.value)
	assert_push_error('scene tree')
