extends GutTest

var chat: LFChatBox
var sent: Array


func before_each():
	chat = add_child_autofree(LFChatBox.new())
	sent = []
	chat.send_requested.connect(func(text): sent.append(text))


func test_enter_sends_the_trimmed_text_and_clears_the_field():
	chat.chat_edit.text = '  hello there  '

	chat.chat_edit.text_submitted.emit(chat.chat_edit.text)

	assert_eq(sent, ['hello there'])
	assert_eq(chat.chat_edit.text, '')


func test_the_send_button_sends_too():
	chat.chat_edit.text = 'ok'

	chat.send_button.pressed.emit()

	assert_eq(sent, ['ok'])


func test_whitespace_only_sends_nothing_and_keeps_the_field():
	chat.chat_edit.text = '   '

	chat.send()

	assert_eq(sent, [])
	assert_eq(chat.chat_edit.text, '   ')


func test_add_line_escapes_name_and_text():
	chat.add_line('[b]Ana', 'try [color=red]this[/color]', Color.RED)

	var shown := chat.chat_log.get_parsed_text()
	assert_string_contains(shown, '[b]Ana: try [color=red]this[/color]', 'brackets show as typed')
	assert_eq(chat.chat_log.get_paragraph_count(), 2, 'one line, then the empty line after its newline')


func test_add_notice_shows_escaped_text():
	chat.add_notice('[Ana] joined')

	assert_string_contains(chat.chat_log.get_parsed_text(), '[Ana] joined')


func test_clear_log_empties_it():
	chat.add_line('Ana', 'hi')

	chat.clear_log()

	assert_eq(chat.chat_log.get_parsed_text(), '')


func test_properties_reach_the_controls():
	var style := StyleBoxFlat.new()

	chat.max_length = 200
	chat.placeholder = 'Type a message…'
	chat.send_text = 'Post'
	chat.log_font_size = 13
	chat.log_min_height = 80.0
	chat.log_style = style

	assert_eq(chat.chat_edit.max_length, 200)
	assert_eq(chat.chat_edit.placeholder_text, 'Type a message…')
	assert_eq(chat.send_button.text, 'Post')
	assert_eq(chat.chat_log.get_theme_font_size(&"normal_font_size"), 13)
	assert_eq(chat.chat_log.custom_minimum_size.y, 80.0)
	assert_eq(chat.chat_log.get_theme_stylebox(&"normal"), style)

	chat.log_style = null
	assert_false(chat.chat_log.has_theme_stylebox_override(&"normal"))


func test_defaults_are_set_before_entering_the_tree():
	var fresh: LFChatBox = autofree(LFChatBox.new())

	assert_eq(fresh.send_button.text, 'Send')
	assert_eq(fresh.send_button.text, LFChatBox.DEFAULT_SEND_TEXT)
	assert_eq(fresh.chat_edit.placeholder_text, 'Say something…')
	assert_eq(fresh.chat_edit.placeholder_text, LFChatBox.DEFAULT_PLACEHOLDER)
	assert_eq(fresh.chat_log.custom_minimum_size.y, LFChatBox.DEFAULT_LOG_MIN_HEIGHT)
	assert_eq(fresh.chat_edit.max_length, 0)
	assert_true(fresh.chat_log.bbcode_enabled)


func test_the_field_is_already_clear_when_send_requested_fires():
	var seen := []
	chat.send_requested.connect(func(_text): seen.append(chat.chat_edit.text))
	chat.chat_edit.text = 'hi'

	chat.send()

	assert_eq(seen, [''])


func test_a_handler_may_put_text_back_in_the_field():
	chat.send_requested.connect(func(text): chat.chat_edit.text = text + ' (not sent)')
	chat.chat_edit.text = 'hi'

	chat.send()

	assert_eq(chat.chat_edit.text, 'hi (not sent)', 'the field is not cleared after the handler ran')


func test_the_field_is_set_to_keep_editing_after_enter():
	assert_true(chat.chat_edit.keep_editing_on_text_submit, 'Godot 4.4+ would end editing on Enter')


func test_the_log_keeps_at_most_max_lines_dropping_the_oldest():
	chat.max_lines = 3

	for i in 5:
		chat.add_line('Ana', 'line %d' % i)
	chat.add_notice('Bo joined')

	assert_eq(chat.line_count(), 3)
	var shown := chat.chat_log.get_parsed_text()
	assert_false(shown.contains('line 2'), 'the oldest lines are gone')
	assert_string_contains(shown, 'Ana: line 3\nAna: line 4\nBo joined')


func test_max_lines_defaults_to_the_log_views_and_zero_keeps_every_line():
	assert_eq(chat.max_lines, LFLogView.DEFAULT_MAX_LINES)
	chat.max_lines = 0

	for i in 150:
		chat.add_line('Ana', str(i))

	assert_eq(chat.line_count(), 150)
	chat.clear_log()
	assert_eq(chat.line_count(), 0)


func test_the_cap_holds_for_remote_text_with_line_breaks():
	chat.max_lines = 5

	for i in 50:
		chat.add_line('Ana\nBo', 'line %d\nfake: spoofed\r\nmore' % i)
		chat.add_notice('notice\n%d' % i)

	assert_eq(chat.line_count(), 5)
	assert_eq(chat.chat_log.get_paragraph_count(), 6, 'five lines, then the empty line after the last newline')
	var shown := chat.chat_log.get_parsed_text()
	assert_string_contains(shown, 'Ana Bo: line 49 fake: spoofed more\nnotice 49\n', 'line breaks became spaces')
	assert_false(shown.contains('line 46'), 'the oldest lines are gone')


func test_a_real_enter_key_in_the_focused_field_sends_and_keeps_editing():
	chat.size = Vector2(300, 150)
	chat.chat_edit.grab_focus()
	chat.chat_edit.edit()
	await wait_process_frames(1)
	chat.chat_edit.insert_text_at_caret('  first  ')

	for pressed in [true, false]:
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.physical_keycode = KEY_ENTER
		enter.pressed = pressed
		get_viewport().push_input(enter)
		await wait_process_frames(1)
	chat.chat_edit.insert_text_at_caret('second')
	chat.send_button.pressed.emit()

	assert_eq(sent, ['first', 'second'])
	assert_true(chat.chat_edit.is_editing(), 'still editing after Enter')


func test_every_kind_of_line_break_becomes_a_space():
	chat.add_line('A\rB', 'a\nb\r\nc d e\u000bf\u000cg\u0085h')

	assert_eq(chat.line_count(), 1)
	assert_eq(chat.chat_log.get_parsed_text(), 'A B: a b c d e f g h\n')
	assert_eq(chat.chat_log.get_paragraph_count(), 2, 'one line, then the empty line after its newline')


func test_remote_text_with_a_vertical_tab_form_feed_or_next_line_draws_as_one_line():
	chat.size = Vector2(1000, 200)
	chat.add_line('Ana', 'hi\u000bBo: fake\u000cCy: fake\u0085Di: fake')
	await wait_process_frames(2)

	assert_eq(chat.chat_log.get_line_count(), 2, 'the message on one drawn line, then the empty line after its newline')


func test_lowering_max_lines_trims_the_log_at_the_next_line():
	for i in 6:
		chat.add_line('Ana', 'line %d' % i)

	chat.max_lines = 2
	assert_eq(chat.line_count(), 6, 'nothing is dropped until a line is added')
	chat.add_notice('Bo joined')

	assert_eq(chat.line_count(), 2)
	assert_eq(chat.chat_log.get_parsed_text(), 'Ana: line 5\nBo joined\n')


func test_a_negative_max_lines_keeps_every_line():
	chat.max_lines = -1

	for i in 120:
		chat.add_notice(str(i))

	assert_eq(chat.line_count(), 120)


func test_a_log_font_size_of_zero_restores_the_theme_font_size():
	var theme_size := chat.chat_log.get_theme_font_size(&"normal_font_size")
	chat.log_font_size = 30

	chat.log_font_size = 0

	assert_false(chat.chat_log.has_theme_font_size_override(&"normal_font_size"))
	assert_eq(chat.chat_log.get_theme_font_size(&"normal_font_size"), theme_size)


func test_a_fresh_chat_box_keeps_the_theme_background_and_follows_new_lines():
	var fresh: LFChatBox = autofree(LFChatBox.new())

	assert_null(fresh.log_style, 'the theme background by default')
	assert_false(fresh.chat_log.has_theme_stylebox_override(&"normal"))
	assert_true(fresh.chat_log.scroll_following, 'the log follows new lines')


func test_the_field_refuses_text_past_max_length():
	chat.max_length = 5
	chat.chat_edit.text = ''

	chat.chat_edit.insert_text_at_caret('abcdefgh')
	chat.send()

	assert_eq(sent, ['abcde'])


func test_the_layout_is_log_then_a_row_of_field_and_button():
	assert_eq(chat.get_child(0), chat.chat_log)
	var row := chat.get_child(1)
	assert_true(row is HBoxContainer)
	assert_eq(row.get_children(), [chat.chat_edit, chat.send_button])
	assert_eq(chat.chat_log.size_flags_vertical, Control.SIZE_EXPAND_FILL)
	assert_eq(chat.chat_edit.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
