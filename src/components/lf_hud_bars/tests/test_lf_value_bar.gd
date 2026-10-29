extends GutTest


class Source:
	extends RefCounted
	signal changed
	var hp := 10.0
	var hp_max := 20.0

	func read() -> Vector2:
		return Vector2(hp, hp_max)


func test_set_values_shows_the_ratio():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())

	bar.set_values(30.0, 120.0)

	assert_eq(bar.current, 30.0)
	assert_eq(bar.maximum, 120.0)
	assert_almost_eq(bar.ratio(), 0.25, 0.0001)
	assert_almost_eq(bar.value / bar.max_value, 0.25, 0.0001)


func test_negative_numbers_count_as_zero_and_overfull_shows_full():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())

	bar.set_values(-5.0, 10.0)
	assert_eq(bar.ratio(), 0.0)
	bar.set_values(50.0, 10.0)
	assert_eq(bar.ratio(), 1.0)
	assert_eq(bar.value, 10.0)
	bar.set_values(5.0, -1.0)
	assert_eq(bar.ratio(), 0.0)
	assert_eq(bar.value, 0.0)


func test_nan_is_reported_and_ignored():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	bar.set_values(3.0, 6.0)

	bar.set_values(NAN, 6.0)

	assert_push_error('NaN')
	assert_eq(bar.current, 3.0)


func test_values_changed_is_emitted():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	watch_signals(bar)

	bar.set_values(1.0, 2.0)

	assert_signal_emitted_with_parameters(bar, 'values_changed', [1.0, 2.0])


func test_easing_slides_the_fill():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	bar.set_values(100.0, 100.0)
	bar.ease_seconds = 0.2

	bar.set_values(0.0, 100.0)

	assert_eq(bar.ratio(), 0.0, 'the numbers change at once')
	assert_gt(bar.value, 50.0, 'the fill has not moved yet')
	await wait_seconds(0.4)
	assert_eq(bar.value, 0.0)


func test_a_second_change_cancels_the_running_ease():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	bar.set_values(100.0, 100.0)
	bar.ease_seconds = 0.2
	bar.set_values(0.0, 100.0)

	bar.ease_seconds = 0.0
	bar.set_values(80.0, 100.0)
	await wait_seconds(0.3)

	assert_eq(bar.value, 80.0)


func test_bind_reads_now_and_on_the_signal():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	var source := Source.new()

	bar.bind(source, &"changed", source.read)
	assert_almost_eq(bar.ratio(), 0.5, 0.0001)
	source.hp = 20.0
	source.changed.emit()

	assert_almost_eq(bar.ratio(), 1.0, 0.0001)


func test_unbind_stops_following():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	var source := Source.new()
	bar.bind(source, &"changed", source.read)

	bar.unbind()
	source.hp = 0.0
	source.changed.emit()

	assert_almost_eq(bar.ratio(), 0.5, 0.0001)


func test_bind_to_a_missing_signal_is_an_error():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	var source := Source.new()

	bar.bind(source, &"nope", source.read)

	assert_push_error('bind needs')


func test_a_signal_with_arguments_works_too():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	var source := Node.new()
	source.add_user_signal('hp_changed', [{'name': 'a', 'type': TYPE_FLOAT}, {'name': 'b', 'type': TYPE_FLOAT}])
	var state := [4.0, 8.0]
	bar.bind(source, &"hp_changed", func() -> Vector2: return Vector2(state[0], state[1]))

	state[0] = 8.0
	source.emit_signal('hp_changed', 8.0, 8.0)

	assert_eq(bar.ratio(), 1.0)
	source.free()


func test_a_read_that_is_not_a_vector2_is_an_error():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())
	var source := Source.new()

	bar.bind(source, &"changed", func() -> int: return 3)

	assert_push_error('Vector2')


func test_fill_color_overrides_the_fill_style():
	var bar: LFValueBar = add_child_autofree(LFValueBar.new())

	bar.fill_color = Color.GREEN

	assert_eq((bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color, Color.GREEN)
