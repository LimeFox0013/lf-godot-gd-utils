extends GutTest


func test_flat_sets_fill_border_corners_and_margin():
	var style := LFStyle.flat(Color.RED, Color.BLUE, 2, 6, 10.0)

	assert_eq(style.bg_color, Color.RED)
	assert_eq(style.border_color, Color.BLUE)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(style.get_border_width(side), 2)
		assert_eq(style.get_content_margin(side), 10.0)
	for corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
		assert_eq(style.get_corner_radius(corner), 6)
	assert_true(style.draw_center)
	assert_true(style.anti_aliasing)


func test_flat_defaults_keep_no_border_and_the_default_margin():
	var style := LFStyle.flat(Color.BLACK)
	var plain := StyleBoxFlat.new()

	assert_eq(style.get_border_width(SIDE_LEFT), 0)
	assert_eq(style.get_corner_radius(CORNER_TOP_LEFT), 0)
	assert_eq(style.get_content_margin(SIDE_LEFT), plain.get_content_margin(SIDE_LEFT))


func test_flat_can_skip_the_fill_and_antialiasing():
	var style := LFStyle.flat(Color.BLACK, Color.WHITE, 1, 0, -1.0, false, false)

	assert_false(style.draw_center)
	assert_false(style.anti_aliasing)


func test_outline_draws_only_the_border():
	var style := LFStyle.outline(Color.YELLOW, 3, 4)

	assert_false(style.draw_center)
	assert_eq(style.border_color, Color.YELLOW)
	assert_eq(style.get_border_width(SIDE_BOTTOM), 3)
	assert_eq(style.get_corner_radius(CORNER_BOTTOM_LEFT), 4)


func test_outline_defaults_to_the_default_width():
	var style := LFStyle.outline(Color.YELLOW)

	assert_eq(style.get_border_width(SIDE_TOP), LFStyle.DEFAULT_OUTLINE_WIDTH)
	assert_eq(style.get_corner_radius(CORNER_TOP_LEFT), 0)


func test_set_button_styles_covers_every_state_including_disabled():
	var button: Button = autofree(Button.new())
	var style := LFStyle.flat(Color.GREEN)

	LFStyle.set_button_styles(button, style)

	for state in LFStyle.BUTTON_STATES:
		assert_true(button.has_theme_stylebox_override(state), str(state))
		assert_eq(button.get_theme_stylebox(state), style)
	assert_true(LFStyle.BUTTON_STATES.has(&"disabled"))


func test_set_button_styles_can_take_a_subset():
	var button: Button = autofree(Button.new())

	LFStyle.set_button_styles(button, LFStyle.flat(Color.GREEN), ['normal'])

	assert_true(button.has_theme_stylebox_override(&"normal"))
	assert_false(button.has_theme_stylebox_override(&"hover"))


func test_project_stylebox_falls_back_when_no_project_theme_has_the_box():
	var fallback := LFStyle.flat(Color.RED)

	assert_eq(LFStyle.project_stylebox(&"no_such_box", &"NoSuchType", fallback), fallback)
	assert_null(LFStyle.project_stylebox(&"no_such_box", &"NoSuchType"))


func test_a_content_margin_of_zero_is_applied():
	var style := LFStyle.flat(Color.BLACK, Color.WHITE, 3, 0, 0.0)

	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(style.get_content_margin(side), 0.0, 'zero padding, not the border-width default')


func test_set_button_styles_shares_one_box_and_takes_string_names():
	var button: Button = autofree(Button.new())
	var style := LFStyle.flat(Color.GREEN)

	LFStyle.set_button_styles(button, style, [&"hover", 'pressed'])

	assert_same(button.get_theme_stylebox(&"hover"), style)
	assert_same(button.get_theme_stylebox(&"pressed"), style)
	assert_false(button.has_theme_stylebox_override(&"normal"))


func test_outline_keeps_the_default_content_margin():
	var style := LFStyle.outline(Color.YELLOW, 3)

	assert_eq(style.get_content_margin(SIDE_LEFT), StyleBoxFlat.new().get_content_margin(SIDE_LEFT))
	assert_eq(style.bg_color, Color.TRANSPARENT)
