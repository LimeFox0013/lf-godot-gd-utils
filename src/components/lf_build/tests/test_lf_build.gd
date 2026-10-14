extends GutTest

## Font size the label test asks for.
const FONT_SIZE := 18
## Outline width, in pixels, the outline test asks for.
const OUTLINE_SIZE := 4
## Wrap width, in pixels, the wrap test asks for.
const WRAP_WIDTH := 280.0
## Margin, in pixels, the margin tests ask for.
const MARGIN_PX := 7


func test_label_sets_text_colour_size_and_parent():
	var parent: VBoxContainer = add_child_autofree(VBoxContainer.new())

	var made := LFBuild.label(parent, 'item_a', Color.ORANGE, FONT_SIZE)

	assert_eq(made.text, 'item_a')
	assert_eq(made.get_parent(), parent)
	assert_true(made.has_theme_color_override(&"font_color"))
	assert_eq(made.get_theme_color(&"font_color"), Color.ORANGE)
	assert_eq(made.get_theme_font_size(&"font_size"), FONT_SIZE)


func test_label_defaults_keep_the_theme():
	var made: Label = autofree(LFBuild.label())

	assert_eq(made.text, '')
	assert_null(made.get_parent())
	assert_false(made.has_theme_color_override(&"font_color"))
	assert_false(made.has_theme_font_size_override(&"font_size"))


func test_wrap_and_outline_return_the_label():
	var made: Label = autofree(Label.new())

	assert_eq(LFBuild.wrap(made, WRAP_WIDTH, TextServer.AUTOWRAP_WORD), made)
	assert_eq(made.autowrap_mode, TextServer.AUTOWRAP_WORD)
	assert_eq(made.custom_minimum_size.x, WRAP_WIDTH)
	assert_eq(LFBuild.outline(made, Color.BLACK, OUTLINE_SIZE), made)
	assert_eq(made.get_theme_color(&"font_outline_color"), Color.BLACK)
	assert_eq(made.get_theme_constant(&"outline_size"), OUTLINE_SIZE)


func test_wrap_defaults_to_smart_word_wrap():
	var made: Label = autofree(LFBuild.wrap(Label.new(), 100.0))

	assert_eq(made.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)


func test_button_is_wired_to_its_callback():
	var parent: HBoxContainer = add_child_autofree(HBoxContainer.new())
	var presses := []

	var made := LFBuild.button(parent, 'Open', func(): presses.append(1), 'Open the item')
	made.pressed.emit()

	assert_eq(made.text, 'Open')
	assert_eq(made.tooltip_text, 'Open the item')
	assert_eq(made.get_parent(), parent)
	assert_eq(presses, [1])


func test_button_without_a_callback_or_parent():
	var made: Button = autofree(LFBuild.button(null, 'Later'))

	assert_null(made.get_parent())
	assert_eq(made.pressed.get_connections(), [])


func test_line_edit_sets_placeholder_tooltip_and_secret():
	var parent: VBoxContainer = add_child_autofree(VBoxContainer.new())

	var made := LFBuild.line_edit(parent, 'Password', 'At least 8 characters', true)

	assert_eq(made.placeholder_text, 'Password')
	assert_eq(made.tooltip_text, 'At least 8 characters')
	assert_true(made.secret)
	assert_eq(made.get_parent(), parent)
	assert_false(autofree(LFBuild.line_edit(null)).secret)


func test_spacer_pushes_siblings_apart():
	var row: HBoxContainer = add_child_autofree(HBoxContainer.new())
	row.size = Vector2(300, 20)
	var left := LFBuild.button(row, 'L')
	LFBuild.spacer(row)
	var right := LFBuild.button(row, 'R')
	await wait_process_frames(2)

	assert_almost_eq(right.position.x + right.size.x, 300.0, 1.0, 'the last button is pushed to the far end')
	assert_eq(left.position.x, 0.0)


func test_fill_parent_insets_the_full_rect():
	var parent: Control = add_child_autofree(Control.new())
	parent.size = Vector2(400, 300)
	var child := Control.new()
	parent.add_child(child)

	assert_eq(LFBuild.fill_parent(child, 10, 20, 30, 40), child)

	assert_eq(child.position, Vector2(10, 20))
	assert_eq(child.size, Vector2(360, 240))


func test_centered_box_on_a_panel_sits_in_the_middle():
	var parent: Control = add_child_autofree(Control.new())
	parent.size = Vector2(800, 600)
	var style := StyleBoxFlat.new()

	var box := LFBuild.centered_box(parent, 200, 12, style)
	LFBuild.label(box, 'Title')
	await wait_process_frames(2)

	var panel := box.get_parent() as PanelContainer
	assert_not_null(panel)
	assert_eq(panel.get_theme_stylebox(&"panel"), style)
	assert_true(panel.get_parent() is CenterContainer)
	assert_eq(box.custom_minimum_size.x, 200.0)
	assert_eq(box.get_theme_constant(&"separation"), 12)
	assert_almost_eq(panel.get_global_rect().get_center(), Vector2(400, 300), Vector2(1, 1))


func test_centered_box_without_a_panel():
	var parent: Control = add_child_autofree(Control.new())

	var box := LFBuild.centered_box(parent, 0, -1, null, false)

	assert_true(box.get_parent() is CenterContainer)
	assert_eq(box.custom_minimum_size.x, 0.0)
	assert_false(box.has_theme_constant_override(&"separation"))


## Tall content scrolls; short content stays centred.
func test_a_scrolling_centered_box_scrolls_only_when_it_does_not_fit():
	var parent: Control = add_child_autofree(Control.new())
	parent.size = Vector2(400, 300)
	var box := LFBuild.centered_box(parent, 100, -1, null, false, true)
	var filler: Control = Control.new()
	filler.custom_minimum_size = Vector2(50, 100)
	box.add_child(filler)
	await wait_process_frames(2)

	var scroll := parent.get_child(0) as ScrollContainer
	assert_not_null(scroll)
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	assert_almost_eq(box.get_global_rect().get_center().y, 150.0, 1.0, 'centred while it fits')
	assert_false(scroll.get_v_scroll_bar().visible, 'no scroll bar while it fits')

	filler.custom_minimum_size = Vector2(50, 900)
	await wait_process_frames(2)
	assert_gt(scroll.get_v_scroll_bar().max_value, 300.0, 'scrolls once taller than the frame')
	assert_true(scroll.get_v_scroll_bar().visible, 'a scroll bar once it does not')
	assert_almost_eq(box.get_global_rect().position.y, 0.0, 1.0)


func test_titled_panel_puts_the_title_first():
	var parent: VBoxContainer = add_child_autofree(VBoxContainer.new())
	var style := StyleBoxFlat.new()

	var box := LFBuild.titled_panel(parent, 'Lifetime', style, 16, 6)

	assert_true(box.get_parent() is PanelContainer)
	assert_eq(box.get_parent().get_parent(), parent)
	assert_eq(box.get_parent().get_theme_stylebox(&"panel"), style)
	assert_eq((box.get_child(0) as Label).text, 'Lifetime')
	assert_eq((box.get_child(0) as Label).get_theme_font_size(&"font_size"), 16)
	assert_eq(box.get_theme_constant(&"separation"), 6)


func test_titled_panel_defaults_keep_the_theme_and_can_stay_unparented():
	var box := LFBuild.titled_panel(null, 'Stats')
	var panel: PanelContainer = autofree(box.get_parent())

	assert_null(panel.get_parent())
	assert_false(panel.has_theme_stylebox_override(&"panel"))
	assert_false(box.has_theme_constant_override(&"separation"))
	assert_false((box.get_child(0) as Label).has_theme_font_size_override(&"font_size"))


func test_a_separation_of_zero_is_applied():
	var parent: Control = add_child_autofree(Control.new())

	var box := LFBuild.centered_box(parent, 0, 0)
	var titled := LFBuild.titled_panel(parent, 'T', null, 0, 0)

	assert_true(box.has_theme_constant_override(&"separation"))
	assert_eq(box.get_theme_constant(&"separation"), 0)
	assert_eq(titled.get_theme_constant(&"separation"), 0)


func test_a_scrolling_centered_box_on_a_panel():
	var parent: Control = add_child_autofree(Control.new())
	parent.size = Vector2(400, 300)
	var style := StyleBoxFlat.new()

	var box := LFBuild.centered_box(parent, 120, -1, style, true, true)
	LFBuild.label(box, 'Title')
	await wait_process_frames(2)

	var panel := box.get_parent() as PanelContainer
	assert_not_null(panel)
	assert_eq(panel.get_theme_stylebox(&"panel"), style)
	assert_true(panel.get_parent() is CenterContainer)
	assert_true(panel.get_parent().get_parent() is ScrollContainer)
	assert_eq(panel.get_parent().get_parent().get_parent(), parent)
	assert_almost_eq(panel.get_global_rect().get_center(), Vector2(200, 150), Vector2(1, 1))


func test_a_label_with_a_parent_but_default_style():
	var parent: VBoxContainer = add_child_autofree(VBoxContainer.new())

	var made := LFBuild.label(parent, 'plain')

	assert_eq(made.get_parent(), parent)
	assert_false(made.has_theme_color_override(&"font_color"))
	assert_false(made.has_theme_font_size_override(&"font_size"))


func test_spacer_without_a_parent_is_unparented_and_click_through():
	var made: Control = autofree(LFBuild.spacer())

	assert_null(made.get_parent())
	assert_eq(made.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(made.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(made.size_flags_vertical, Control.SIZE_EXPAND_FILL)


func test_on_commit_fires_on_enter_and_on_focus_loss():
	var edit: LineEdit = autofree(LineEdit.new())
	var calls := []

	assert_eq(LFBuild.on_commit(edit, func(): calls.append(1)), edit)
	edit.text_submitted.emit('typed')
	edit.focus_exited.emit()

	assert_eq(calls.size(), 2)


func test_margin_sets_all_four_sides_and_parent():
	var parent: Control = add_child_autofree(Control.new())

	var made := LFBuild.margin(parent, MARGIN_PX)

	assert_eq(made.get_parent(), parent)
	for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		assert_eq(made.get_theme_constant(side), MARGIN_PX)


func test_margin_without_parent_is_unparented():
	var made: MarginContainer = autofree(LFBuild.margin(null, MARGIN_PX))

	assert_null(made.get_parent())


func test_spin_box_sets_range_step_and_clamped_value():
	var parent: Control = add_child_autofree(Control.new())

	var made := LFBuild.spin_box(parent, 1.0, 10.0, 0.5, 99.0)

	assert_eq(made.get_parent(), parent)
	assert_eq([made.min_value, made.max_value, made.step], [1.0, 10.0, 0.5])
	assert_eq(made.value, 10.0)
