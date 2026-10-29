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
	assert_push_warning("unreadable bindings")
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
	assert_push_warning("no such action: no_such_action")


func test_kind_of_and_is_bindable():
	assert_eq(LFInputRebinder.kind_of(_key(KEY_W)), LFInputRebinder.Kind.KEYBOARD)
	assert_eq(LFInputRebinder.kind_of(_button(JOY_BUTTON_A)), LFInputRebinder.Kind.PAD)
	assert_eq(LFInputRebinder.kind_of(_stick(JOY_AXIS_LEFT_X, 1.0)), LFInputRebinder.Kind.PAD)
	assert_eq(LFInputRebinder.kind_of(InputEventMouseButton.new()), -1)
	assert_true(LFInputRebinder.is_bindable(_stick(JOY_AXIS_LEFT_X, -LFInputRebinder.AXIS_THRESHOLD)))
	assert_false(LFInputRebinder.is_bindable(_stick(JOY_AXIS_LEFT_X, 0.59)))
	assert_false(LFInputRebinder.is_bindable(InputEventKey.new()), "a key with no code")


func test_same_compares_physical_key_button_and_stick_direction():
	assert_true(LFInputRebinder.same(_key(KEY_A), _key(KEY_A)))
	assert_false(LFInputRebinder.same(_key(KEY_A), _key(KEY_B)))
	assert_true(LFInputRebinder.same(_stick(JOY_AXIS_LEFT_X, 0.7), _stick(JOY_AXIS_LEFT_X, 1.0)))
	assert_false(LFInputRebinder.same(_stick(JOY_AXIS_LEFT_X, 1.0), _stick(JOY_AXIS_LEFT_X, -1.0)))
	assert_false(LFInputRebinder.same(_key(KEY_A), _button(JOY_BUTTON_A)))


func test_modifiers_are_dropped_and_the_stick_is_stored_fully_pushed():
	var event := _key(KEY_W)
	event.shift_pressed = true
	_rebinder.rebind(JUMP, event)
	var key: InputEventKey = _rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD)[0]
	assert_false(key.shift_pressed)
	_rebinder.rebind(JUMP, _stick(JOY_AXIS_LEFT_Y, 0.8))
	var stick: InputEventJoypadMotion = _rebinder.events_of(JUMP, LFInputRebinder.Kind.PAD)[0]
	assert_eq(stick.axis_value, 1.0)


func test_a_swap_with_nothing_to_hand_over_leaves_the_other_action_empty():
	InputMap.action_erase_events(JUMP)
	var changed := _rebinder.rebind(JUMP, _key(KEY_A))
	assert_eq(changed, [LEFT])
	assert_eq(_rebinder.label_of(LEFT, LFInputRebinder.Kind.KEYBOARD), "-")


func test_describe_other_sticks_and_unknown_events():
	assert_eq(LFInputRebinder.describe(_stick(JOY_AXIS_LEFT_Y, -1.0)), "Stick Up")
	assert_eq(LFInputRebinder.describe(_stick(JOY_AXIS_RIGHT_X, 1.0)), "Axis %d+" % JOY_AXIS_RIGHT_X)
	assert_eq(LFInputRebinder.describe(InputEventMouseButton.new()), "?")


func test_the_saved_file_is_versioned_json():
	assert_true(_rebinder.save())
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(data.version), LFInputRebinder.FILE_VERSION)
	assert_true(data.bindings.has(str(JUMP)))


func test_save_to_an_unwritable_path_fails():
	var rebinder := LFInputRebinder.new("user://no_such_folder_rebinder/x.json", [JUMP])
	assert_false(rebinder.save())
	assert_push_error_count(1)


func test_an_action_missing_from_the_input_map_has_no_bindings():
	assert_eq(_rebinder.events_of(&"test_rebind_nope", LFInputRebinder.Kind.KEYBOARD), [])
	assert_eq(_rebinder.label_of(&"test_rebind_nope", LFInputRebinder.Kind.PAD), "-")
	assert_push_warning_count(2, "events_of and label_of each warn")


func test_a_tracked_action_erased_later_is_skipped_by_reset_save_and_load():
	assert_true(_rebinder.save())
	InputMap.erase_action(JUMP)
	_rebinder.reset()
	assert_false(InputMap.has_action(JUMP))
	assert_eq(_rebinder.events_of(JUMP, LFInputRebinder.Kind.KEYBOARD), [])
	assert_true(_rebinder.save())
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_false(data.bindings.has(str(JUMP)))
	assert_true(_rebinder.load_saved())
	assert_false(InputMap.has_action(JUMP))
	assert_push_warning_count(4, "reset, events_of, save and load_saved each warn")
	InputMap.add_action(JUMP)  # after_each erases it
