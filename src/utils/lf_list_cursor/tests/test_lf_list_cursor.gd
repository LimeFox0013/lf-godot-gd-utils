extends GutTest


func test_clamp_index_keeps_an_index_inside_the_list():
	assert_eq(LFListCursor.clamp_index(-3, 4), 0)
	assert_eq(LFListCursor.clamp_index(2, 4), 2)
	assert_eq(LFListCursor.clamp_index(9, 4), 3)


func test_clamp_index_of_an_empty_list_is_zero():
	assert_eq(LFListCursor.clamp_index(5, 0), 0)
	assert_eq(LFListCursor.clamp_index(-5, 0), 0)


func test_step_moves_one_and_stops_at_both_ends():
	assert_eq(LFListCursor.step(1, 1, 3), 2)
	assert_eq(LFListCursor.step(2, 1, 3), 2)
	assert_eq(LFListCursor.step(1, -1, 3), 0)
	assert_eq(LFListCursor.step(0, -1, 3), 0)


func test_marker_is_shown_only_on_the_cursor_row():
	assert_eq(LFListCursor.marker(2, 2, "> "), "> ")
	assert_eq(LFListCursor.marker(1, 2, "> "), "")
	assert_eq(LFListCursor.marker(1, 2, "> ", "  "), "  ")


func test_a_cursor_starts_on_its_index_clamped_to_the_count():
	assert_eq(LFListCursor.new(3).index, 0)
	assert_eq(LFListCursor.new(3, 2).index, 2)
	assert_eq(LFListCursor.new(3, 7).index, 2)


func test_move_reports_whether_the_cursor_changed():
	var cursor := LFListCursor.new(3)
	assert_false(cursor.move(-1))
	assert_true(cursor.move(1))
	assert_true(cursor.move(5))
	assert_eq(cursor.index, 2)
	assert_false(cursor.move(1))


func test_shrinking_the_count_pulls_the_cursor_back():
	var cursor := LFListCursor.new(5, 4)
	cursor.set_count(2)
	assert_eq(cursor.index, 1)
	cursor.set_count(0)
	assert_eq(cursor.index, 0)


func test_growing_the_count_keeps_the_cursor_where_it_was():
	var cursor := LFListCursor.new(2, 1)
	cursor.set_count(6)
	assert_eq(cursor.index, 1)


func test_move_to_clamps_and_marker_at_follows_the_index():
	var cursor := LFListCursor.new(3)
	cursor.move_to(9)
	assert_eq(cursor.index, 2)
	assert_eq(cursor.marker_at(2, "> "), "> ")
	assert_eq(cursor.marker_at(0, "> ", "  "), "  ")
