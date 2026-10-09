extends GutTest

var chart: LFBarChart


func before_each():
	chart = add_child_autofree(LFBarChart.new())
	chart.size = Vector2(300, 124)


func test_no_values_draws_no_bars():
	assert_eq(chart.bar_rects(), [])


func test_the_largest_value_reaches_the_top_and_bars_share_one_baseline():
	chart.values = [2, 4, 1]

	var rects := chart.bar_rects()

	assert_eq(rects.size(), 3)
	assert_almost_eq(rects[1].position.y, 24.0, 0.01, 'the tallest bar ends top_padding below the top')
	assert_almost_eq(rects[1].size.y, 96.0, 0.01)
	assert_almost_eq(rects[0].size.y, 48.0, 0.01)
	for rect in rects:
		assert_almost_eq(rect.end.y, 120.0, 0.01, 'baseline bottom_padding above the bottom')


func test_bars_are_centred_in_equal_slots():
	chart.values = [1, 1, 1]

	var rects := chart.bar_rects()

	assert_almost_eq(rects[0].size.x, 60.0, 0.01, '0.6 of a 100 px slot')
	assert_almost_eq(rects[0].position.x, 20.0, 0.01)
	assert_almost_eq(rects[2].position.x, 220.0, 0.01)
	chart.bar_ratio = 1.0
	assert_almost_eq(chart.bar_rects()[0].size.x, 100.0, 0.01)


func test_zeros_and_negatives_stay_flat():
	chart.values = [0, -3, 0]

	for rect in chart.bar_rects():
		assert_eq(rect.size.y, 0.0)


func test_values_are_copied():
	var source := [1, 2]
	chart.values = source
	source.append(3)

	assert_eq(chart.values, [1, 2])


func test_value_labels():
	assert_eq(chart.format_value(5), '5')
	assert_eq(chart.format_value(5.0), '5')
	assert_eq(chart.format_value(2.5), '2.5')
	chart.value_text = func(v): return '%d pts' % v
	assert_eq(chart.format_value(7), '7 pts')


func test_setting_values_redraws():
	var draws := []
	chart.draw.connect(func(): draws.append(true))
	await wait_process_frames(1)
	draws.clear()

	chart.values = [3, 1]
	await wait_process_frames(1)

	assert_gt(draws.size(), 0)


func test_paddings_move_the_top_and_the_baseline():
	chart.values = [1]
	chart.top_padding = 10.0
	chart.bottom_padding = 0.0

	var rect := chart.bar_rects()[0]

	assert_almost_eq(rect.position.y, 10.0, 0.01)
	assert_almost_eq(rect.end.y, 124.0, 0.01)


func test_every_style_property_redraws():
	var draws := []
	chart.draw.connect(func(): draws.append(true))
	var changes := {
		'bar_color': Color.RED,
		'label_color': Color.BLUE,
		'axis_color': Color.GREEN,
		'font_size': 20,
		'bar_ratio': 0.5,
		'show_values': false,
		'top_padding': 8.0,
		'bottom_padding': 2.0,
	}
	for property: String in changes:
		await wait_process_frames(1)
		draws.clear()

		chart.set(property, changes[property])
		await wait_process_frames(1)

		assert_eq(chart.get(property), changes[property], property)
		assert_gt(draws.size(), 0, '%s redraws' % property)


func test_nan_and_infinite_values_draw_flat_and_leave_the_scale_to_the_others():
	set_values([NAN, 2, INF, 4, -INF])

	var rects := chart.bar_rects()

	assert_eq(rects[0].size.y, 0.0, 'NaN draws as 0')
	assert_eq(rects[2].size.y, 0.0, 'INF draws as 0')
	assert_eq(rects[4].size.y, 0.0)
	assert_almost_eq(rects[3].size.y, 96.0, 0.01, 'the largest finite value still reaches the top')
	assert_almost_eq(rects[1].size.y, 48.0, 0.01)


func test_huge_and_non_finite_labels_never_print_a_wrapped_integer():
	assert_eq(chart.format_value(1e20), '100000000000000000000')
	assert_eq(chart.format_value(INF), 'inf')
	assert_eq(chart.format_value(NAN), 'nan')
	assert_eq(chart.format_value(-0.0000001), '0', 'a near-zero negative prints 0, not -0')


func set_values(new_values: Array) -> void:
	chart.values = new_values


func test_properties_start_at_their_defaults():
	var fresh: LFBarChart = autofree(LFBarChart.new())

	assert_eq(fresh.bar_color, LFBarChart.DEFAULT_BAR_COLOR)
	assert_eq(fresh.label_color, LFBarChart.DEFAULT_LABEL_COLOR)
	assert_eq(fresh.axis_color, LFBarChart.DEFAULT_AXIS_COLOR)
	assert_eq(fresh.font_size, LFBarChart.DEFAULT_FONT_SIZE)
	assert_eq(fresh.bar_ratio, LFBarChart.DEFAULT_BAR_RATIO)
	assert_eq(fresh.top_padding, LFBarChart.DEFAULT_TOP_PADDING)
	assert_eq(fresh.bottom_padding, LFBarChart.DEFAULT_BOTTOM_PADDING)


func test_value_labels_are_centred_on_their_bars_just_above_them():
	chart.values = [5, 1234567, 10]

	var bars := chart.bar_rects()
	var labels := chart.value_label_rects()

	assert_eq(labels.size(), 3)
	for i in 3:
		assert_almost_eq(labels[i].get_center().x, bars[i].get_center().x, 0.001, 'label %d is centred on its bar' % i)
		assert_almost_eq(labels[i].end.y, bars[i].position.y - 4.0, 0.001, 'and sits just above it')
		assert_gt(labels[i].size.x, 0.0)


func test_many_bars_keep_a_one_pixel_minimum_width():
	var many := []
	many.resize(1000)
	many.fill(1)
	chart.values = many

	var rects := chart.bar_rects()

	assert_eq(rects.size(), 1000)
	assert_eq(rects[0].size.x, 1.0, 'a 0.3 px slot still draws a 1 px bar')
	assert_almost_eq(rects[999].get_center().x, 299.85, 0.001, 'centred in its slot')


func test_a_bar_ratio_above_one_fills_the_slot_and_no_more():
	chart.values = [1, 1, 1]
	chart.bar_ratio = 3.0

	assert_almost_eq(chart.bar_rects()[0].size.x, 100.0, 0.01)
	assert_almost_eq(chart.bar_rects()[0].position.x, 0.0, 0.01)


func test_paddings_taller_than_the_chart_keep_bars_flat_on_the_baseline():
	chart.size = Vector2(300, 20)
	chart.values = [5, 2]

	for rect in chart.bar_rects():
		assert_eq(rect.size.y, 0.0, 'no negative height')
		assert_almost_eq(rect.position.y, 16.0, 0.01, 'on the baseline')


func test_fractions_print_with_at_most_two_decimals_and_negatives_keep_their_sign():
	assert_eq(chart.format_value(3.14159), '3.14')
	assert_eq(chart.format_value(-2), '-2')
	assert_eq(chart.format_value(-INF), '-inf')
	assert_eq(chart.format_value(-1e20), '-100000000000000000000')
	assert_eq(chart.format_value(9.0e15), '9000000000000000', 'at the limit it prints through String.num')
	assert_eq(chart.format_value(8.0e15), '8000000000000000', 'below it through int()')


func test_large_values_with_a_fraction_keep_their_decimals():
	assert_eq(chart.format_value(123456.78), '123456.78', 'not rounded to a whole number')
	assert_eq(chart.format_value(70000.5), '70000.5')
	assert_eq(chart.format_value(2.999), '3', 'rounds to a whole number at two decimals')


func test_no_values_have_no_labels():
	assert_eq(chart.value_label_rects(), [])


func test_value_text_shapes_the_label_rects_too():
	chart.values = [5]
	var plain := chart.value_label_rects()[0].size.x
	chart.value_text = func(v): return '%d points scored' % v

	assert_gt(chart.value_label_rects()[0].size.x, plain)


## Drawing cannot be read back headless; this only checks both label settings draw
## without crashing.
func test_draws_with_and_without_value_labels_without_crashing():
	chart.values = [3, NAN, 1]
	await wait_process_frames(1)
	chart.show_values = false
	await wait_process_frames(1)

	assert_eq(chart.bar_rects().size(), 3)


func test_a_value_that_is_not_a_number_draws_flat_and_prints_as_text():
	chart.values = [4, null, 'x']

	var rects := chart.bar_rects()

	assert_eq(rects.size(), 3)
	assert_almost_eq(rects[0].size.y, 96.0, 0.01)
	assert_eq(rects[1].size.y, 0.0)
	assert_eq(rects[2].size.y, 0.0)
	assert_eq(chart.format_value(null), '<null>')
	assert_eq(chart.format_value('x'), 'x')
