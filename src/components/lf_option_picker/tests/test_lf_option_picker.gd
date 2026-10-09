extends GutTest

var picker: OptionButton


func before_each():
	picker = OptionButton.new()
	add_child_autofree(picker)


func test_fill_labels_and_carries_values_and_selects_the_given_one():
	var items := [{ 'id': 7, 'name': 'Seven' }, { 'id': 9, 'name': 'Nine' }]

	LFOptionPicker.fill(picker, items, func(item): return item['name'], func(item): return item['id'], 9)

	assert_eq(picker.item_count, 2)
	assert_eq([picker.get_item_text(0), picker.get_item_text(1)], ['Seven', 'Nine'])
	assert_eq([picker.get_item_metadata(0), picker.get_item_metadata(1)], [7, 9])
	assert_eq(picker.selected, 1)
	assert_eq(LFOptionPicker.selected_value(picker), 9)


func test_without_a_value_callable_the_item_itself_is_the_value():
	LFOptionPicker.fill(picker, ['a', 'b'], func(item): return item.to_upper())

	assert_true(LFOptionPicker.select_value(picker, 'b'))
	assert_eq(LFOptionPicker.selected_value(picker), 'b')


func test_an_unknown_value_leaves_the_selection_and_an_empty_picker_gives_the_fallback():
	LFOptionPicker.fill(picker, [1, 2], func(item): return str(item), Callable(), 2)

	assert_false(LFOptionPicker.select_value(picker, 5))
	assert_false(LFOptionPicker.select_value(picker, '2'), 'a String never matches an int')
	assert_eq(LFOptionPicker.selected_value(picker), 2)
	picker.clear()
	assert_eq(LFOptionPicker.selected_value(picker, -1), -1)


func test_filling_with_a_value_no_item_carries_selects_nothing_and_says_so():
	assert_false(LFOptionPicker.fill(picker, ['x', 'y'], func(item): return item, Callable(), 'zzz'))

	assert_eq(picker.selected, -1, 'the first item is not shown in its place')
	assert_eq(LFOptionPicker.selected_value(picker, 'fallback'), 'fallback')


func test_fill_reports_whether_an_item_ends_up_selected():
	assert_true(LFOptionPicker.fill(picker, [1, 2], func(item): return str(item), Callable(), 2))
	assert_true(LFOptionPicker.fill(picker, [1, 2], func(item): return str(item)), 'with nothing asked for, the first item')
	assert_eq(LFOptionPicker.selected_value(picker), 1)
	assert_false(LFOptionPicker.fill(picker, [], func(item): return str(item)), 'nothing to select')


func test_numbers_match_across_int_and_float_and_text_across_string_and_string_name():
	LFOptionPicker.fill(picker, [1, 2.5, 'a', &'b'], func(item): return str(item))

	assert_true(LFOptionPicker.select_value(picker, 1.0))
	assert_eq(picker.selected, 0)
	assert_true(LFOptionPicker.select_value(picker, &'a'))
	assert_eq(picker.selected, 2)
	assert_true(LFOptionPicker.select_value(picker, 'b'))
	assert_eq(picker.selected, 3)


func test_fill_never_emits_item_selected():
	var emitted := []
	picker.item_selected.connect(func(index): emitted.append(index))

	LFOptionPicker.fill(picker, ['a', 'b'], func(item): return item, Callable(), 'b')

	assert_eq(emitted, [])


func test_an_item_without_a_value_reads_as_the_fallback():
	LFOptionPicker.fill(picker, ['a'], func(item): return item)
	picker.add_item('Custom')
	picker.select(1)

	assert_eq(LFOptionPicker.selected_value(picker, 'none'), 'none')


func test_value_selected_hands_the_chosen_items_value_to_the_callback():
	var values := []
	LFOptionPicker.fill(picker, [{ 'id': 7 }, { 'id': 9 }], func(item): return str(item['id']), func(item): return item['id'])
	picker.add_item('Custom')
	var connection := LFOptionPicker.value_selected(picker, func(value): values.append(value))

	picker.item_selected.emit(1)
	picker.item_selected.emit(2)
	assert_eq(values, [9, null], 'an item without a value hands over null')

	picker.item_selected.disconnect(connection)
	picker.item_selected.emit(0)
	assert_eq(values, [9, null], 'the returned callable disconnects it')


func test_an_invalid_label_callable_leaves_the_picker_as_it_was():
	LFOptionPicker.fill(picker, ['a', 'b'], func(item): return item, Callable(), 'b')

	assert_false(LFOptionPicker.fill(picker, ['x'], Callable()))

	assert_push_error('label')
	assert_eq(picker.item_count, 2)
	assert_eq(LFOptionPicker.selected_value(picker), 'b')


func test_fill_can_give_each_item_an_icon():
	var red := PlaceholderTexture2D.new()
	var blue := PlaceholderTexture2D.new()
	var items := [{"name": "Red", "icon": red}, {"name": "Blue", "icon": blue}, {"name": "None", "icon": null}]

	LFOptionPicker.fill(picker, items, func(item): return item.name, Callable(), null, func(item): return item.icon)

	assert_eq(picker.get_item_icon(0), red)
	assert_eq(picker.get_item_icon(1), blue)
	assert_null(picker.get_item_icon(2), "null shows no icon")


func test_without_an_icon_callable_items_have_no_icon():
	LFOptionPicker.fill(picker, ["a"], func(item): return item)

	assert_null(picker.get_item_icon(0))


func test_select_value_null_selects_a_null_valued_item():
	picker.add_item("Pick one")
	picker.add_item("Custom")
	picker.set_item_metadata(0, 1)
	picker.select(0)

	assert_true(LFOptionPicker.select_value(picker, null))

	assert_eq(picker.selected, 1, "the item without a value carries null")


func test_a_refill_replaces_every_earlier_item_and_value():
	LFOptionPicker.fill(picker, ['a', 'b', 'c'], func(item): return item, Callable(), 'c')

	LFOptionPicker.fill(picker, [{ 'id': 1, 'name': 'One' }], func(item): return item['name'], func(item): return item['id'])

	assert_eq(picker.item_count, 1)
	assert_eq(picker.get_item_text(0), 'One')
	assert_eq(LFOptionPicker.selected_value(picker), 1)
	assert_false(LFOptionPicker.select_value(picker, 'c'), 'the old values are gone')


func test_an_icon_callable_returning_something_other_than_a_texture_shows_no_icon():
	LFOptionPicker.fill(picker, ['a'], func(item): return item, Callable(), null, func(_item): return 'not a texture')

	assert_null(picker.get_item_icon(0))
	assert_eq(picker.get_item_text(0), 'a')


func test_value_selected_reports_a_real_choice_made_through_the_popup():
	var values := []
	LFOptionPicker.fill(picker, [{ 'id': 'easy' }, { 'id': 'hard' }], func(item): return item['id'], func(item): return item['id'])
	LFOptionPicker.value_selected(picker, func(value): values.append(value))

	picker.get_popup().index_pressed.emit(1)

	assert_eq(values, ['hard'])
	assert_eq(LFOptionPicker.selected_value(picker), 'hard')


func test_value_selected_with_an_invalid_callback_connects_nothing():
	LFOptionPicker.fill(picker, ['a'], func(item): return item)

	var connection := LFOptionPicker.value_selected(picker, Callable())

	assert_false(connection.is_valid(), 'an empty Callable comes back')
	assert_eq(picker.item_selected.get_connections().size(), 0, 'nothing was connected')
	assert_push_error('needs a valid callback')
