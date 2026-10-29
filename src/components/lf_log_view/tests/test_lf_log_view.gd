extends GutTest


func test_append_adds_lines_oldest_first():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())

	var line := log_view.append('first')
	log_view.append('second', Color.RED)

	assert_eq(log_view.line_count(), 2)
	assert_eq(log_view.line_text(0), 'first')
	assert_eq(log_view.line_text(1), 'second')
	assert_eq(log_view.lines.get_child(0), line)
	assert_eq((log_view.lines.get_child(1) as Label).get_theme_color(&"font_color"), Color.RED)
	assert_eq(log_view.line_text(5), '')


func test_101_appends_keep_the_newest_100_lines():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())

	assert_eq(LFLogView.DEFAULT_MAX_LINES, 100)
	for i in LFLogView.DEFAULT_MAX_LINES + 1:
		log_view.append('line %d' % i)

	assert_eq(log_view.line_count(), LFLogView.DEFAULT_MAX_LINES)
	assert_eq(log_view.line_text(0), 'line 1', 'the oldest one was dropped')
	assert_eq(log_view.line_text(LFLogView.DEFAULT_MAX_LINES - 1), 'line %d' % LFLogView.DEFAULT_MAX_LINES)
	await wait_process_frames(1) # the dropped line is freed at the end of the frame


func test_max_lines_of_zero_keeps_everything():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.max_lines = 0

	for i in 130:
		log_view.append(str(i))

	assert_eq(log_view.line_count(), 130)


func test_font_size_applies_to_new_lines():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.font_size = 11

	assert_eq(log_view.append('x').get_theme_font_size(&"font_size"), 11)


func test_clear_removes_every_line_at_once():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.append('a')
	log_view.append('b')

	log_view.clear()

	assert_eq(log_view.line_count(), 0)
	await wait_process_frames(1) # the removed lines are freed at the end of the frame


func test_follow_keeps_the_newest_line_in_view():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.size = Vector2(200, 60)
	for i in 30:
		log_view.append('line %d' % i)
	await wait_process_frames(3)

	var bar := log_view.get_v_scroll_bar()
	assert_gt(bar.max_value, 60.0)
	assert_almost_eq(float(log_view.scroll_vertical), bar.max_value - bar.page, 1.0)


func test_without_follow_the_view_stays_at_the_top():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.follow = false
	log_view.size = Vector2(200, 60)
	for i in 30:
		log_view.append('line %d' % i)
	await wait_process_frames(3)

	assert_eq(log_view.scroll_vertical, 0)


func test_a_fresh_log_has_no_lines_wraps_words_and_never_scrolls_sideways():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())

	assert_eq(log_view.line_count(), 0)
	assert_eq(log_view.line_text(0), '')
	assert_eq(log_view.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	var line := log_view.append('a long line that wraps')
	assert_eq(line.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)


func test_line_text_out_of_range_on_either_side_is_empty():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.append('only')

	assert_eq(log_view.line_text(-1), '')
	assert_eq(log_view.line_text(1), '')
	assert_eq(log_view.line_text(0), 'only')


func test_without_a_colour_or_font_size_a_line_keeps_the_theme_values():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())

	var line := log_view.append('plain')

	assert_false(line.has_theme_color_override(&"font_color"))
	assert_false(line.has_theme_font_size_override(&"font_size"))


func test_a_negative_max_lines_keeps_everything():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.max_lines = -5

	for i in 120:
		log_view.append(str(i))

	assert_eq(log_view.line_count(), 120)


func test_lowering_max_lines_trims_on_the_next_append_keeping_the_newest():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	for i in 10:
		log_view.append('line %d' % i)

	log_view.max_lines = 3
	assert_eq(log_view.line_count(), 10, 'nothing is dropped until a line is added')
	log_view.append('line 10')

	assert_eq(log_view.line_count(), 3)
	assert_eq([log_view.line_text(0), log_view.line_text(2)], ['line 8', 'line 10'])
	await wait_process_frames(1)


func test_a_log_works_before_it_enters_the_tree():
	var log_view: LFLogView = autofree(LFLogView.new())
	log_view.max_lines = 2

	for i in 3:
		log_view.append(str(i))

	assert_eq(log_view.line_count(), 2)
	assert_eq(log_view.line_text(0), '1')
	await wait_process_frames(1)


func test_at_the_cap_an_append_still_scrolls_a_reader_who_scrolled_up_to_the_newest_line():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.size = Vector2(200, 60)
	log_view.max_lines = 30
	for i in 30:
		log_view.append('line %d' % i)
	await wait_process_frames(3)
	log_view.scroll_vertical = 0

	log_view.append('line 30')
	await wait_process_frames(3)

	var bar := log_view.get_v_scroll_bar()
	assert_eq(log_view.line_text(29), 'line 30')
	assert_almost_eq(float(log_view.scroll_vertical), bar.max_value - bar.page, 1.0)


class ChatLine:
	extends MarginContainer
	var text := ''


func test_line_factory_makes_the_lines_and_the_cap_still_holds():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.max_lines = 2
	log_view.line_factory = func(text: String, color: Variant) -> Control:
		var bubble := ChatLine.new()
		bubble.text = text
		bubble.set_meta('color', color)
		return bubble

	var first: Control = log_view.append('one', Color.RED)
	log_view.append('two')
	log_view.append('three')

	assert_true(first is ChatLine)
	assert_eq(first.get_meta('color'), Color.RED)
	assert_eq(log_view.line_count(), 2)
	assert_eq(log_view.line_text(0), 'two')
	assert_eq(log_view.line_text(1), 'three')
	await wait_process_frames(1)


func test_line_scene_root_gets_the_text_property():
	var scene := PackedScene.new()
	var root := ChatLine.new()
	scene.pack(root)
	root.free()
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.line_scene = scene

	var line: Control = log_view.append('hello')

	assert_true(line is ChatLine)
	assert_eq((line as ChatLine).text, 'hello')
	assert_eq(log_view.line_text(0), 'hello')


func test_line_scene_label_root_gets_the_colour():
	var scene := PackedScene.new()
	var root := Label.new()
	scene.pack(root)
	root.free()
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.line_scene = scene

	var line: Label = log_view.append('x', Color.BLUE) as Label

	assert_eq(line.text, 'x')
	assert_eq(line.get_theme_color(&"font_color"), Color.BLUE)


func test_a_factory_beats_a_scene():
	var scene := PackedScene.new()
	var root := Label.new()
	scene.pack(root)
	root.free()
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.line_scene = scene
	log_view.line_factory = func(_text: String, _color: Variant) -> Control: return ChatLine.new()

	var line: Control = log_view.append('x')
	assert_true(line is ChatLine)


func test_a_factory_returning_a_non_control_falls_back_to_a_label():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.line_factory = func(_text: String, _color: Variant) -> Variant: return null

	var line: Control = log_view.append('fallback')

	assert_push_error('line_factory')
	assert_true(line is Label)
	assert_eq(log_view.line_text(0), 'fallback')


func test_custom_lines_still_follow_the_newest():
	var log_view: LFLogView = add_child_autofree(LFLogView.new())
	log_view.size = Vector2(100, 50)
	log_view.line_factory = func(_text: String, _color: Variant) -> Control:
		var line := ChatLine.new()
		line.custom_minimum_size = Vector2(10, 40)
		return line

	for i in 10:
		log_view.append(str(i))
	await wait_process_frames(3)

	assert_gt(log_view.scroll_vertical, 0)
