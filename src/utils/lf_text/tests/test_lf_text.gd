extends GutTest

const REPLACEMENT := '�'


func _bytes(values: Array) -> PackedByteArray:
	return PackedByteArray(values)


func test_valid_utf8_decodes_unchanged():
	assert_eq(LFText.decode_utf8_lossy('héllo, мир, 😀'.to_utf8_buffer()), 'héllo, мир, 😀')
	assert_eq(LFText.decode_utf8_lossy(PackedByteArray()), '')


func test_an_invalid_byte_becomes_a_replacement_character_without_logging():
	assert_eq(LFText.decode_utf8_lossy(_bytes([0x61, 0xFF, 0x62])), 'a%sb' % REPLACEMENT)
	assert_engine_error_count(0)


func test_each_malformed_byte_is_replaced_and_the_rest_kept():
	var cases := [
		[[0x80], REPLACEMENT, 'a stray continuation byte'],
		[[0xC3], REPLACEMENT, 'a truncated two-byte sequence at the end'],
		[[0xC0, 0xAF], REPLACEMENT + REPLACEMENT, 'an overlong encoding'],
		[[0xE0, 0x80, 0xAF], REPLACEMENT.repeat(3), 'an overlong three-byte encoding'],
		[[0xED, 0xA0, 0x80], REPLACEMENT.repeat(3), 'a UTF-16 surrogate'],
		[[0xF4, 0x90, 0x80, 0x80], REPLACEMENT.repeat(4), 'past U+10FFFF'],
		[[0xC3, 0xA9, 0xFF, 0xC3, 0xA9], 'é%sé' % REPLACEMENT, 'good characters around a bad byte'],
	]
	for c in cases:
		assert_eq(LFText.decode_utf8_lossy(_bytes(c[0])), c[1], c[2])
	assert_engine_error_count(0)


func test_safe_cut_never_splits_a_character():
	var bytes := 'ééé'.to_utf8_buffer()	# 6 bytes, two per character
	assert_eq(LFText.utf8_safe_cut(bytes, 5), 4, 'backs off to the start of the third é')
	assert_eq(LFText.utf8_safe_cut(bytes, 4), 4, 'already on a boundary')
	assert_eq(bytes.slice(0, LFText.utf8_safe_cut(bytes, 5)).get_string_from_utf8(), 'éé')


func test_safe_cut_at_or_past_the_end_is_the_whole_buffer():
	var bytes := 'abc'.to_utf8_buffer()
	assert_eq(LFText.utf8_safe_cut(bytes, 3), 3)
	assert_eq(LFText.utf8_safe_cut(bytes, 10), 3)
	assert_eq(LFText.utf8_safe_cut(PackedByteArray(), 4), 0)


func test_safe_cut_with_no_boundary_returns_the_limit_so_a_loop_progresses():
	var bytes := _bytes([0xF0, 0x9F, 0x98, 0x80, 0x61])	# 😀a
	assert_eq(LFText.utf8_safe_cut(bytes, 2), 2)
	assert_eq(LFText.utf8_safe_cut(bytes, 0), 0)
	assert_eq(LFText.utf8_safe_cut(bytes, -3), 0)


func test_clock_shows_minutes_and_seconds():
	assert_eq(LFText.clock(0), '0:00')
	assert_eq(LFText.clock(5), '0:05')
	assert_eq(LFText.clock(75), '1:15')
	assert_eq(LFText.clock(3599), '59:59')


func test_clock_rounds_a_fraction_up_by_default():
	assert_eq(LFText.clock(59.5), '1:00')
	assert_eq(LFText.clock(0.2), '0:01')
	assert_eq(LFText.clock(59.5, false), '0:59', 'or down when asked')


func test_clock_is_never_negative():
	assert_eq(LFText.clock(-1), '0:00')
	assert_eq(LFText.clock(-0.5), '0:00')
	assert_eq(LFText.clock(-90, false), '0:00')


func test_clock_shows_no_time_for_infinity_nan_or_seconds_past_the_int_range():
	assert_eq(LFText.clock(INF), LFText.CLOCK_NO_TIME, 'INF: no limit, not a garbage hour count')
	assert_eq(LFText.clock(NAN), LFText.CLOCK_NO_TIME)
	assert_eq(LFText.clock(1e30), LFText.CLOCK_NO_TIME)
	assert_eq(LFText.clock(INF, false), LFText.CLOCK_NO_TIME)
	assert_eq(LFText.CLOCK_NO_TIME, '--:--')
	assert_eq(LFText.clock(-INF), '0:00', 'minus infinity is below zero')


func test_clock_shows_hours_from_one_hour():
	assert_eq(LFText.clock(3600), '1:00:00')
	assert_eq(LFText.clock(3661), '1:01:01')
	assert_eq(LFText.clock(3599.5), '1:00:00', 'rounding up can reach the hour')


func test_plural_counts_with_the_right_noun():
	assert_eq(LFText.plural(1, 'item'), '1 item')
	assert_eq(LFText.plural(2, 'item'), '2 items')
	assert_eq(LFText.plural(0, 'item'), '0 items')
	assert_eq(LFText.plural(-1, 'item'), '-1 items')


func test_plural_takes_an_irregular_form():
	assert_eq(LFText.plural(3, 'box', 'boxes'), '3 boxes')
	assert_eq(LFText.plural(1, 'box', 'boxes'), '1 box')


func test_bbcode_escape_neutralises_every_open_bracket():
	assert_eq(LFText.bbcode_escape('[b]hi[/b]'), '[lb]b]hi[lb]/b]')
	assert_eq(LFText.bbcode_escape('plain'), 'plain')
	assert_eq(LFText.bbcode_escape(''), '')


func test_escaped_text_renders_literally_in_a_rich_text_label():
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	add_child_autofree(label)
	label.text = LFText.bbcode_escape('[color=red]x[/color]')
	assert_eq(label.get_parsed_text(), '[color=red]x[/color]')


func test_decoding_stops_at_the_first_zero_byte():
	assert_eq(LFText.decode_utf8_lossy(_bytes([0x61, 0x00, 0x62])), 'a')
	assert_eq(LFText.decode_utf8_lossy(_bytes([0x61, 0x00, 0xFF])), 'a', 'also on the replacing path')


func test_the_narrowed_second_byte_ranges_accept_their_valid_characters():
	var cases := [
		[[0xE0, 0xA0, 0x80], String.chr(0x0800), 'U+0800, the first three-byte character after lead 0xE0'],
		[[0xED, 0x9F, 0xBF], String.chr(0xD7FF), 'U+D7FF, the last character before the surrogates'],
		[[0xEE, 0x80, 0x80], String.chr(0xE000), 'U+E000, just past the surrogates'],
		[[0xF0, 0x90, 0x80, 0x80], String.chr(0x10000), 'U+10000, the first four-byte character'],
		[[0xF4, 0x8F, 0xBF, 0xBF], String.chr(0x10FFFF), 'U+10FFFF, the last character'],
	]
	for c in cases:
		assert_eq(LFText.decode_utf8_lossy(_bytes(c[0])), c[1], c[2])
	assert_engine_error_count(0)


func test_more_malformed_sequences_are_replaced_byte_by_byte():
	var cases := [
		[[0xF0, 0x8F, 0xBF, 0xBF], REPLACEMENT.repeat(4), 'an overlong four-byte encoding'],
		[[0xF5, 0x80, 0x80, 0x80], REPLACEMENT.repeat(4), 'a lead byte past 0xF4'],
		[[0xC1, 0xBF], REPLACEMENT.repeat(2), 'lead 0xC1 is always overlong'],
		[[0xE2, 0x82, 0x41], REPLACEMENT + REPLACEMENT + 'A', 'a bad third byte; the ASCII after it is kept'],
		[[0xF0, 0x9F, 0x98, 0x41], REPLACEMENT.repeat(3) + 'A', 'a bad fourth byte'],
		[[0xE2, 0x82], REPLACEMENT.repeat(2), 'a three-byte sequence cut short at the end'],
		[[0xF0, 0x9F, 0x98], REPLACEMENT.repeat(3), 'a four-byte sequence cut short at the end'],
		[[0xC3, 0x41], REPLACEMENT + 'A', 'a lead byte followed by ASCII'],
		[[0xFF, 0xF0, 0x9F, 0x98, 0x80, 0xE2, 0x82, 0xAC], REPLACEMENT + '😀€', 'whole multi-byte characters after a bad byte survive'],
	]
	for c in cases:
		assert_eq(LFText.decode_utf8_lossy(_bytes(c[0])), c[1], c[2])
	assert_engine_error_count(0)


func test_safe_cut_backs_off_over_three_and_four_byte_characters():
	var bytes := 'a€😀'.to_utf8_buffer()	# 1 + 3 + 4 bytes
	assert_eq(LFText.utf8_safe_cut(bytes, 1), 1)
	assert_eq(LFText.utf8_safe_cut(bytes, 2), 1, 'inside the euro sign')
	assert_eq(LFText.utf8_safe_cut(bytes, 3), 1)
	assert_eq(LFText.utf8_safe_cut(bytes, 4), 4)
	assert_eq(LFText.utf8_safe_cut(bytes, 7), 4, 'inside the emoji')
	assert_eq(LFText.utf8_safe_cut(bytes, 8), 8)


func test_cutting_in_a_loop_rebuilds_the_text_exactly():
	var text := 'héllo wörld — 😀 €'
	var buffer := text.to_utf8_buffer()
	var rebuilt := ''
	var chunks := 0
	while not buffer.is_empty():
		var cut := LFText.utf8_safe_cut(buffer, 4)
		rebuilt += LFText.decode_utf8_lossy(buffer.slice(0, cut))
		buffer = buffer.slice(cut)
		chunks += 1
		assert_lt(chunks, 100, 'the loop makes progress')
	assert_eq(rebuilt, text)


func test_clock_rounds_down_when_asked_and_covers_the_int_limit():
	assert_eq(LFText.clock(0.9, false), '0:00')
	assert_eq(LFText.clock(3600.9, false), '1:00:00')
	assert_eq(LFText.clock(9223372036854775808.0), LFText.CLOCK_NO_TIME, 'exactly 2^63')
	assert_ne(LFText.clock(9223372036854774784.0), LFText.CLOCK_NO_TIME, 'the largest float below 2^63 still shows hours')
	assert_eq(LFText.clock(360000), '100:00:00', 'hours are not capped at two digits')


func test_plural_ignores_the_plural_form_for_one_and_uses_it_otherwise():
	assert_eq(LFText.plural(0, 'mouse', 'mice'), '0 mice')
	assert_eq(LFText.plural(-1, 'mouse', 'mice'), '-1 mice')
