extends GutTest

## A keyboard stands in for a gamepad through a key map; presses are filtered by device;
## keys and buttons get one consistent on-screen name.

const KEY_MAP := {KEY_ENTER: JOY_BUTTON_START, KEY_SPACE: JOY_BUTTON_A, KEY_C: JOY_BUTTON_X}


func _key(keycode: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


func _pad(button: JoyButton, device := 0, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	event.pressed = pressed
	return event


func test_the_keyboard_maps_a_key_onto_the_button_it_stands_for():
	assert_eq(LFInputKeys.button_of(_key(KEY_SPACE), LFInputKeys.KEYBOARD, KEY_MAP), JOY_BUTTON_A)
	assert_eq(LFInputKeys.button_of(_key(KEY_ENTER), LFInputKeys.KEYBOARD, KEY_MAP), JOY_BUTTON_START)
	assert_eq(LFInputKeys.button_of(_key(KEY_Z), LFInputKeys.KEYBOARD, KEY_MAP), -1, 'unmapped key')


func test_a_physical_only_key_still_maps():
	var event := InputEventKey.new()
	event.physical_keycode = KEY_C
	event.pressed = true

	assert_eq(LFInputKeys.button_of(event, LFInputKeys.KEYBOARD, KEY_MAP), JOY_BUTTON_X)


func test_releases_and_echoes_are_not_presses():
	assert_eq(LFInputKeys.button_of(_key(KEY_SPACE, false), LFInputKeys.KEYBOARD, KEY_MAP), -1)
	assert_eq(LFInputKeys.button_of(_key(KEY_SPACE, true, true), LFInputKeys.KEYBOARD, KEY_MAP), -1)
	assert_eq(LFInputKeys.button_of(_pad(JOY_BUTTON_A, 0, false), 0, KEY_MAP), -1)


func test_a_pad_press_counts_only_for_its_own_device():
	assert_eq(LFInputKeys.button_of(_pad(JOY_BUTTON_B, 1), 1, KEY_MAP), JOY_BUTTON_B)
	assert_eq(LFInputKeys.button_of(_pad(JOY_BUTTON_B, 2), 1, KEY_MAP), -1, 'another pad')
	assert_eq(LFInputKeys.button_of(_pad(JOY_BUTTON_A, 0), LFInputKeys.KEYBOARD, KEY_MAP), -1, 'a pad is not the keyboard')
	assert_eq(LFInputKeys.button_of(_key(KEY_SPACE), 0, KEY_MAP), -1, 'the keyboard is not pad 0')
	assert_eq(LFInputKeys.button_of(null, 0, KEY_MAP), -1)


func test_is_press_matches_keys_or_buttons_and_skips_echoes_unless_asked():
	assert_true(LFInputKeys.is_press(_key(KEY_ESCAPE), [KEY_ESCAPE], [JOY_BUTTON_BACK]))
	assert_true(LFInputKeys.is_press(_pad(JOY_BUTTON_BACK, 3), [KEY_ESCAPE], [JOY_BUTTON_BACK]), 'any device')
	assert_false(LFInputKeys.is_press(_key(KEY_ESCAPE, false), [KEY_ESCAPE]))
	assert_false(LFInputKeys.is_press(_key(KEY_ESCAPE, true, true), [KEY_ESCAPE]))
	assert_true(LFInputKeys.is_press(_key(KEY_W, true, true), [KEY_W], [], true), 'a held key repeats when echoes are allowed')
	assert_false(LFInputKeys.is_press(_key(KEY_Q), [KEY_ESCAPE], [JOY_BUTTON_BACK]))
	assert_false(LFInputKeys.is_press(_pad(JOY_BUTTON_A), [KEY_ESCAPE]))
	assert_false(LFInputKeys.is_press(InputEventMouseButton.new(), [KEY_ESCAPE]))


func test_key_names_use_overrides_then_godots_names():
	assert_eq(LFInputKeys.key_name(KEY_ESCAPE), 'Esc')
	assert_eq(LFInputKeys.key_name(KEY_SPACE), 'Space')
	assert_eq(LFInputKeys.key_name(KEY_F1), 'F1')
	assert_eq(LFInputKeys.key_name(KEY_SPACE, {KEY_SPACE: 'Space bar'}), 'Space bar')


func test_hint_names_the_key():
	assert_eq(LFInputKeys.hint('label_a', KEY_SPACE), 'label_a  [Space]')
	assert_eq(LFInputKeys.hint('label_b', KEY_ESCAPE), 'label_b  [Esc]')
	assert_eq(LFInputKeys.hint('label_c', KEY_F1, '%s (%s)'), 'label_c (F1)')


func test_bind_hint_labels_the_button_and_keeps_it_out_of_focus():
	var button: Button = autofree(Button.new())

	assert_eq(LFInputKeys.bind_hint(button, 'label_d', KEY_SPACE), button)
	assert_eq(button.text, 'label_d  [Space]')
	assert_eq(button.focus_mode, Control.FOCUS_NONE)


func test_pad_buttons_are_named_per_style():
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_A), 'A')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_LEFT_SHOULDER), 'LB')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_START), 'Start')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_A, LFInputKeys.PadStyle.PLAYSTATION), 'Cross')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_A, LFInputKeys.PadStyle.NINTENDO), 'B', 'the bottom button')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_DPAD_UP, LFInputKeys.PadStyle.PLAYSTATION), 'D-pad Up')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_PADDLE1), '?')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_PADDLE1, LFInputKeys.PadStyle.XBOX, ''), '')


## The keyboard player sees its keys' names, a pad player its buttons'.
func test_button_name_reads_the_device_table():
	var key_names := {JOY_BUTTON_A: 'Space', JOY_BUTTON_X: 'C', JOY_BUTTON_START: 'Enter'}

	assert_eq(LFInputKeys.button_name(JOY_BUTTON_A, LFInputKeys.KEYBOARD, key_names), 'Space')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_START, LFInputKeys.KEYBOARD, key_names), 'Enter')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_B, LFInputKeys.KEYBOARD, key_names), '?', 'not in the table')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_A, 0, key_names), 'A')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_RIGHT_SHOULDER, 1, key_names), 'RB')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_START, 0, key_names), 'Start')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_Y, 0, {}, LFInputKeys.PadStyle.PLAYSTATION), 'Triangle')


func test_key_names_for_derives_hint_names_from_the_key_map():
	var names := LFInputKeys.key_names_for({KEY_SPACE: JOY_BUTTON_A, KEY_ESCAPE: JOY_BUTTON_BACK, KEY_W: JOY_BUTTON_DPAD_UP, KEY_UP: JOY_BUTTON_DPAD_UP})

	assert_eq(names[JOY_BUTTON_A], 'Space')
	assert_eq(names[JOY_BUTTON_BACK], 'Esc')
	assert_eq(names[JOY_BUTTON_DPAD_UP], 'W / Up', 'every key bound to the button, in map order')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_A, LFInputKeys.KEYBOARD, names), 'Space')


func test_key_names_use_the_overrides_by_default() -> void:
	assert_eq(LFInputKeys.key_name(KEY_ESCAPE), LFInputKeys.KEY_NAME_OVERRIDES[KEY_ESCAPE])
	assert_eq(LFInputKeys.key_name(KEY_ESCAPE), "Esc")


func test_hints_use_the_hint_format_by_default() -> void:
	var expected := LFInputKeys.HINT_FORMAT % ["Jump", LFInputKeys.key_name(KEY_SPACE)]
	assert_eq(LFInputKeys.hint("Jump", KEY_SPACE), expected)


func test_bind_hint_takes_key_name_overrides_like_hint():
	var button: Button = autofree(Button.new())
	LFInputKeys.bind_hint(button, 'label_e', KEY_ESCAPE, LFInputKeys.HINT_FORMAT, {KEY_ESCAPE: 'Back'})
	assert_eq(button.text, 'label_e  [Back]')


func test_is_press_of_nothing_is_false():
	assert_false(LFInputKeys.is_press(null, [KEY_ESCAPE], [JOY_BUTTON_BACK]))


func test_is_press_matches_a_physical_only_key():
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true

	assert_true(LFInputKeys.is_press(event, [KEY_ESCAPE]))


func test_a_non_key_event_on_the_keyboard_presses_nothing():
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true

	assert_eq(LFInputKeys.button_of(click, LFInputKeys.KEYBOARD, KEY_MAP), -1)
	assert_eq(LFInputKeys.button_of(click, 0, KEY_MAP), -1, 'nor on a pad')


func test_an_unknown_pad_style_reads_as_xbox():
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_LEFT_SHOULDER, 99 as LFInputKeys.PadStyle), 'LB')


func test_the_nintendo_style_names_its_system_buttons():
	var style := LFInputKeys.PadStyle.NINTENDO
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_BACK, style), '-')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_START, style), '+')
	assert_eq(LFInputKeys.joy_button_name(JOY_BUTTON_X, style), 'Y')
	assert_eq(LFInputKeys.button_name(JOY_BUTTON_PADDLE1, 0, {}, style, 'none'), 'none', 'a pad fallback')


func test_key_names_for_applies_the_overrides():
	var names := LFInputKeys.key_names_for({KEY_SPACE: JOY_BUTTON_A, KEY_ESCAPE: JOY_BUTTON_BACK}, {KEY_SPACE: 'Bar'})

	assert_eq(names[JOY_BUTTON_A], 'Bar')
	assert_eq(names[JOY_BUTTON_BACK], 'Escape', 'replacing the overrides drops the default Esc')
