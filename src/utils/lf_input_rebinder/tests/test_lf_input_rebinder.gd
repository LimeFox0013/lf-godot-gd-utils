extends GutTest

const PATH := "user://test_rebinder.json"
const LEFT := &"test_rebind_left"
const RIGHT := &"test_rebind_right"
const JUMP := &"test_rebind_jump"

var _rebinder: LFInputRebinder


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	return event


func _stick(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func before_each() -> void:
	for action in [LEFT, RIGHT, JUMP]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
	InputMap.action_add_event(LEFT, _key(KEY_A))
	InputMap.action_add_event(LEFT, _stick(JOY_AXIS_LEFT_X, -1.0))
	InputMap.action_add_event(RIGHT, _key(KEY_D))
	InputMap.action_add_event(RIGHT, _stick(JOY_AXIS_LEFT_X, 1.0))
	InputMap.action_add_event(JUMP, _key(KEY_SPACE))
	InputMap.action_add_event(JUMP, _button(JOY_BUTTON_A))
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	_rebinder = LFInputRebinder.new(PATH, [LEFT, RIGHT, JUMP])


func after_each() -> void:
	for action in [LEFT, RIGHT, JUMP]:
		InputMap.erase_action(action)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_a_key_replaces_the_keyboard_binding_and_keeps_the_pad_one():
	_rebinder.rebind(JUMP, _key(KEY_W))
	var keys := _rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)
	assert_eq(keys.size(), 1)
	assert_eq(keys[0].physical_keycode, KEY_W)
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.PAD).size(), 1, "the pad binding stays")
	assert_true(InputMap.action_has_event(JUMP, _key(KEY_W)))


func test_a_pad_button_replaces_the_pad_bindings():
	_rebinder.rebind(LEFT, _button(JOY_BUTTON_X))
	var pad := _rebinder.events_of(LEFT, LFInputRebinder.Kind.PAD)
	assert_eq(pad.size(), 1, "the stick is replaced")
	assert_true(pad[0] is InputEventJoypadButton)


func test_taking_a_key_another_action_has_swaps_them():
	var changed := _rebinder.rebind(JUMP, _key(KEY_A))
	assert_eq(changed, [LEFT])
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_A)
	assert_eq(_rebinder.events_of(LEFT, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_SPACE, "left got the jump key")


func test_what_cannot_be_bound_changes_nothing():
	var echo := _key(KEY_W)
	echo.echo = true
	var released := _key(KEY_W)
	released.pressed = false
	for event in [echo, released, _stick(JOY_AXIS_LEFT_X, 0.2), InputEventMouseButton.new()]:
		assert_eq(_rebinder.rebind(JUMP, event).size(), 0)
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_SPACE)
	assert_eq(_rebinder.rebind(&"unknown_action", _key(KEY_W)).size(), 0)


func test_reset_returns_to_the_starting_bindings():
	_rebinder.rebind(JUMP, _key(KEY_W))
	_rebinder.rebind(LEFT, _button(JOY_BUTTON_X))
	_rebinder.reset(JUMP)
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_SPACE)
	assert_true(_rebinder.events_of(LEFT, LFInputRebinder.Kind.PAD)[0] is InputEventJoypadButton, "only the named action is reset")
	_rebinder.reset()
	assert_true(_rebinder.events_of(LEFT, LFInputRebinder.Kind.PAD)[0] is InputEventJoypadMotion)


func test_saved_bindings_come_back():
	_rebinder.rebind(JUMP, _key(KEY_W))
	_rebinder.rebind(RIGHT, _stick(JOY_AXIS_LEFT_Y, -1.0))
	assert_true(_rebinder.save())
	_rebinder.reset()
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_SPACE)
	assert_true(_rebinder.load_saved())
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_W)
	var stick: InputEventJoypadMotion = _rebinder.events_of(RIGHT, LFInputRebinder.Kind.PAD)[0]
	assert_eq(stick.axis, JOY_AXIS_LEFT_Y)
	assert_eq(stick.axis_value, -1.0)


func test_no_file_or_a_broken_one_changes_nothing():
	assert_false(_rebinder.load_saved())
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	assert_false(_rebinder.load_saved())
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_SPACE)


func test_a_file_that_lacks_an_action_leaves_it_alone():
	_rebinder.rebind(JUMP, _key(KEY_W))
	_rebinder.save()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "bindings": {"test_rebind_jump": [{"type": "key", "code": KEY_Q}]}}))
	file.close()
	_rebinder.load_saved()
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_Q)
	assert_eq(_rebinder.events_of(LEFT, LFInputRebinder.Kind.KEYBOARD)[0].physical_keycode, KEY_A)


func test_names_for_labels():
	assert_eq(LFInputRebinder.describe(_button(JOY_BUTTON_A)), "A")
	assert_eq(LFInputRebinder.describe(_button(JOY_BUTTON_A), LFInputKeys.PadStyle.PLAYSTATION), "Cross")
	assert_eq(LFInputRebinder.describe(_stick(JOY_AXIS_LEFT_X, -1.0)), "Stick Left")
	assert_eq(_rebinder.label_of(JUMP, LFInputRebinder.Kind.PAD), "A")
	assert_eq(_rebinder.label_of(JUMP, LFInputRebinder.Kind.KEYBOARD), "Space")


func test_an_action_without_a_binding_of_a_kind_reads_as_a_dash():
	InputMap.action_erase_events(JUMP)
	assert_eq(_rebinder.label_of(JUMP, LFInputRebinder.Kind.PAD), "-")


func test_unknown_actions_are_not_tracked():
	var rebinder := LFInputRebinder.new(PATH, [JUMP, &"no_such_action"])
	assert_eq(rebinder.actions, [JUMP])
