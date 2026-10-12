extends GutTest

const MIN_SIZE := Vector2(40.0, 60.0)
const MAX_SIZE := Vector2(300.0, 120.0)

var field: LFAutoSizeTextEdit
var font: Font
var font_size: int


func before_each():
	field = LFAutoSizeTextEdit.new()
	field.min_size = MIN_SIZE
	field.max_size = MAX_SIZE
	add_child_autofree(field)
	font = field.get_theme_font("font")
	font_size = field.get_theme_font_size("font_size")


func _line_height() -> float:
	return font.get_height(font_size)


func _margins() -> Vector2:
	return field.get_theme_stylebox("normal").get_minimum_size()


func _fitted(text: String) -> Vector2:
	return LFAutoSizeTextEdit.fitted_size(text, font, font_size, _margins(), MIN_SIZE, MAX_SIZE)


func test_an_empty_field_has_the_minimum_size():
	assert_eq(field.refit(), MIN_SIZE)
	assert_eq(field.custom_minimum_size, MIN_SIZE)


func test_width_follows_the_longest_line():
	var short := _fitted("hello world")
	var longer := _fitted("hello world, hello world")
	assert_gt(short.x, MIN_SIZE.x)
	assert_gt(longer.x, short.x)
	assert_lt(longer.x, MAX_SIZE.x)


func test_width_is_the_text_plus_margins_and_padding():
	var text := "hello world"
	var expected := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x) + _margins().x + LFAutoSizeTextEdit.DEFAULT_EXTRA_WIDTH_PADDING
	assert_eq(_fitted(text).x, expected)


func test_width_stops_at_the_maximum_and_the_text_wraps_taller():
	var long_line := "word ".repeat(80)
	var fitted := _fitted(long_line)
	assert_eq(fitted.x, MAX_SIZE.x)
	assert_gt(fitted.y, MIN_SIZE.y, "wrapped lines add height")


func test_height_grows_with_lines_and_stops_at_the_maximum():
	var two := _fitted("one\ntwo")
	var four := _fitted("a\nb\nc\nd")
	assert_gt(four.y, two.y)
	assert_eq(_fitted("x\n".repeat(60)).y, MAX_SIZE.y)


func test_a_few_lines_take_their_height_plus_margins():
	var text := "a\nb\nc\nd"
	var fitted := _fitted(text)
	var lines := 4.0
	assert_gte(fitted.y, minf(lines * _line_height() + _margins().y, MAX_SIZE.y) - 1.0)
	assert_lte(fitted.y, MAX_SIZE.y)


func test_a_maximum_below_the_minimum_counts_as_the_minimum():
	var tiny := LFAutoSizeTextEdit.fitted_size("a long line of text here", font, font_size, Vector2.ZERO, Vector2(200, 80), Vector2(10, 10))
	assert_eq(tiny, Vector2(200, 80))


func test_changing_the_text_resizes_the_field_at_the_end_of_the_frame():
	field.text = "hello world, this is a line"
	field.text_changed.emit()
	await get_tree().process_frame
	assert_eq(field.custom_minimum_size, _fitted(field.text))
	assert_gt(field.custom_minimum_size.x, MIN_SIZE.x)


func test_setting_the_text_property_alone_resizes_too():
	field.text = "hello world, this is a line"
	await get_tree().process_frame
	assert_eq(field.custom_minimum_size, _fitted(field.text))


func test_changing_the_size_limits_resizes_the_field():
	field.text = "hello world, this is a line"
	field.min_size = Vector2(400, 30)
	field.max_size = Vector2(500, 120)
	await get_tree().process_frame
	assert_eq(field.custom_minimum_size.x, 400.0)


func test_many_changes_in_a_frame_measure_once():
	var sizes: Array[Vector2] = []
	for i in 5:
		field.text = "text %d" % i
	await get_tree().process_frame
	sizes.append(field.custom_minimum_size)
	assert_eq(sizes[0], LFAutoSizeTextEdit.fitted_size("text 4", font, font_size, _margins(), MIN_SIZE, MAX_SIZE))


func test_refit_outside_the_tree_changes_nothing():
	var loose := LFAutoSizeTextEdit.new()
	assert_eq(loose.refit(), Vector2.ZERO)
	loose.free()


func test_the_field_wraps_at_word_boundaries_by_default():
	assert_eq(field.wrap_mode, TextEdit.LINE_WRAPPING_BOUNDARY)
