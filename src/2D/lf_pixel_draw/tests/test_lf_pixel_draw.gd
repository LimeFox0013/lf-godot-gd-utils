extends GutTest

const RED := Color.RED
const BLUE := Color.BLUE

var _root: Node2D


func before_each() -> void:
	_root = add_child_autofree(Node2D.new())


func _rects(node: Node) -> Array:
	return node.get_children().filter(func(c): return c is ColorRect)


func _covered(holder: Node) -> Dictionary:
	# Every integer cell covered by a child rect, keyed by Vector2i.
	var cells := {}
	for r in _rects(holder):
		for x in range(int(r.position.x), int(r.position.x + r.size.x)):
			for y in range(int(r.position.y), int(r.position.y + r.size.y)):
				cells[Vector2i(x, y)] = r.color
	return cells


func test_rect_is_added_with_position_size_and_color() -> void:
	var r := LFPixelDraw.rect(_root, 3, 4, 5, 6, RED)
	assert_eq(r.get_parent(), _root)
	assert_eq(r.position, Vector2(3, 4))
	assert_eq(r.size, Vector2(5, 6))
	assert_eq(r.color, RED)
	assert_eq(r.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_rect_with_null_parent_is_left_unattached() -> void:
	var r := LFPixelDraw.rect(null, 0, 0, 1, 1, RED)
	assert_null(r.get_parent())
	r.free()


func test_disc_is_centred_symmetric_and_filled() -> void:
	var holder := LFPixelDraw.disc(_root, 50, 60, 5, RED, 1.0)
	assert_eq(holder.position, Vector2(50, 60))
	var cells := _covered(holder)
	assert_true(cells.has(Vector2i(0, 0)))
	assert_true(cells.has(Vector2i(-1, -1)))
	for cell in cells:
		assert_true(cells.has(Vector2i(-cell.x - 1, cell.y)), "mirrored left and right")
		assert_true(cells.has(Vector2i(cell.x, -cell.y - 1)), "mirrored top and bottom")
		assert_lte(Vector2(cell).length(), 7.1, "stays inside the disc's reach")


func test_disc_step_makes_blocky_strips() -> void:
	var holder := LFPixelDraw.disc(_root, 0, 0, 8, RED, 4.0)
	for r in _rects(holder):
		assert_eq(r.size.y, 4.0)
		assert_eq(fmod(r.size.x, 4.0), 0.0)


func test_disc_with_no_radius_or_step_draws_nothing() -> void:
	assert_eq(_rects(LFPixelDraw.disc(_root, 0, 0, 0, RED)).size(), 0)
	assert_eq(_rects(LFPixelDraw.disc(_root, 0, 0, 5, RED, 0.0)).size(), 0)


func test_line_horizontal_vertical_and_diagonal() -> void:
	assert_eq(_covered(LFPixelDraw.line(_root, Vector2(0, 0), Vector2(4, 0), RED)).size(), 5)
	assert_eq(_covered(LFPixelDraw.line(_root, Vector2(2, 1), Vector2(2, 3), RED)).size(), 3)
	var diagonal := _covered(LFPixelDraw.line(_root, Vector2(0, 0), Vector2(3, 3), RED))
	assert_eq(diagonal.size(), 4)
	for i in 4:
		assert_true(diagonal.has(Vector2i(i, i)))


func test_line_reaches_both_ends_in_either_direction() -> void:
	var cells := _covered(LFPixelDraw.line(_root, Vector2(6, 2), Vector2(0, 0), RED))
	assert_true(cells.has(Vector2i(0, 0)))
	assert_true(cells.has(Vector2i(6, 2)))


func test_line_snaps_to_the_pixel_grid() -> void:
	var holder := LFPixelDraw.line(_root, Vector2(0, 0), Vector2(20, 0), RED, 5.0)
	var xs := _rects(holder).map(func(r): return r.position.x)
	assert_eq(xs, [0.0, 5.0, 10.0, 15.0, 20.0])
	for r in _rects(holder):
		assert_eq(r.size, Vector2(5, 5))


func test_outline_is_hollow() -> void:
	var holder := LFPixelDraw.outline(_root, 10, 20, 6, 5, RED, 1.0)
	assert_eq(holder.position, Vector2(10, 20))
	var cells := _covered(holder)
	assert_eq(cells.size(), 6 * 5 - 4 * 3, "the border of a 6x5 box")
	assert_false(cells.has(Vector2i(2, 2)), "the middle is empty")
	assert_true(cells.has(Vector2i(0, 0)))
	assert_true(cells.has(Vector2i(5, 4)))


func test_outline_thicker_than_the_box_becomes_solid() -> void:
	assert_eq(_covered(LFPixelDraw.outline(_root, 0, 0, 4, 4, RED, 99.0)).size(), 16)


func test_pattern_draws_palette_colors_and_skips_the_rest() -> void:
	var holder := LFPixelDraw.pattern(_root, ["X.B", ".X."], {"X": RED, "B": BLUE})
	var cells := _covered(holder)
	assert_eq(cells.size(), 3)
	assert_eq(cells[Vector2i(0, 0)], RED)
	assert_eq(cells[Vector2i(2, 0)], BLUE)
	assert_eq(cells[Vector2i(1, 1)], RED)
	assert_false(cells.has(Vector2i(1, 0)))


func test_pattern_merges_runs_into_one_rect() -> void:
	var holder := LFPixelDraw.pattern(_root, ["XXXX", "XXBB"], {"X": RED, "B": BLUE})
	assert_eq(_rects(holder).size(), 3, "one run on top, one red and one blue below")
	assert_eq(_covered(holder).size(), 8)


func test_pattern_scales_and_places() -> void:
	var holder := LFPixelDraw.pattern(_root, ["XX"], RED, 3.0, Vector2(10, 20))
	assert_eq(holder.position, Vector2(10, 20))
	var r: ColorRect = _rects(holder)[0]
	assert_eq(r.size, Vector2(6, 3))


func test_pattern_with_a_single_color_uses_x() -> void:
	assert_eq(_covered(LFPixelDraw.pattern(_root, ["XoX"], BLUE)).size(), 2)


func test_pattern_ignores_a_bad_palette_and_pixel() -> void:
	assert_eq(_rects(LFPixelDraw.pattern(_root, ["XX"], "nope")).size(), 0)
	assert_eq(_rects(LFPixelDraw.pattern(_root, ["XX"], RED, 0.0)).size(), 0)


func test_pattern_size_is_longest_row_by_row_count() -> void:
	assert_eq(LFPixelDraw.pattern_size(["X", "XXX", "XX"]), Vector2i(3, 3))
	assert_eq(LFPixelDraw.pattern_size([]), Vector2i(0, 0))


func test_pattern_texture_has_one_pixel_per_art_pixel() -> void:
	var texture := LFPixelDraw.pattern_texture(["X.", ".B"], {"X": RED, "B": BLUE})
	var image := texture.get_image()
	assert_eq(image.get_size(), Vector2i(2, 2))
	assert_eq(image.get_pixel(0, 0), RED)
	assert_eq(image.get_pixel(1, 1), BLUE)
	assert_eq(image.get_pixel(1, 0).a, 0.0)


func test_pattern_texture_of_nothing_is_one_transparent_pixel() -> void:
	var image := LFPixelDraw.pattern_texture([], RED).get_image()
	assert_eq(image.get_size(), Vector2i(1, 1))
	assert_eq(image.get_pixel(0, 0).a, 0.0)


func test_sprite_is_one_nearest_filtered_scaled_node() -> void:
	var node := LFPixelDraw.sprite(_root, ["XX", "XX"], RED, 4.0, Vector2(8, 9))
	assert_eq(node.get_parent(), _root)
	assert_eq(node.scale, Vector2(4, 4))
	assert_eq(node.position, Vector2(8, 9))
	assert_false(node.centered)
	assert_eq(node.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(node.texture.get_size(), Vector2(2, 2))


func test_every_glyph_is_five_rows_of_equal_width() -> void:
	for character in LFPixelDraw.FONT:
		var rows: Array = LFPixelDraw.FONT[character]
		assert_eq(rows.size(), LFPixelDraw.GLYPH_HEIGHT, character)
		for row in rows:
			assert_eq(String(row).length(), String(rows[0]).length(), "%s rows are equally wide" % character)
			assert_true(String(row).replace("0", "").replace("1", "").is_empty(), "%s uses only 0 and 1" % character)


func test_font_covers_letters_and_digits() -> void:
	for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
		assert_true(LFPixelDraw.FONT.has(character), character)


func test_text_draws_a_known_glyph() -> void:
	var cells := _covered(LFPixelDraw.text(_root, "I", 0, 0, 1, RED))
	# I = 111 / 010 / 010 / 010 / 111
	assert_eq(cells.size(), 3 + 1 + 1 + 1 + 3)
	assert_true(cells.has(Vector2i(1, 2)))
	assert_false(cells.has(Vector2i(0, 2)))


func test_text_positions_scales_and_lowercase_matches_uppercase() -> void:
	var upper := LFPixelDraw.text(_root, "AB", 7, 9, 2, RED)
	var lower := LFPixelDraw.text(_root, "ab", 7, 9, 2, RED)
	assert_eq(upper.position, Vector2(7, 9))
	assert_eq(_covered(upper), _covered(lower))
	assert_eq(upper.get_children().map(func(c): return c.size), lower.get_children().map(func(c): return c.size))


func test_text_advances_by_glyph_width_plus_gap() -> void:
	var cells := _covered(LFPixelDraw.text(_root, "II", 0, 0, 1, RED))
	assert_true(cells.has(Vector2i(4, 0)), "the second I starts after 3 + 1")
	assert_false(cells.has(Vector2i(3, 0)), "the gap stays empty")


func test_text_space_and_unknown_characters() -> void:
	var spaced := _covered(LFPixelDraw.text(_root, "I I", 0, 0, 1, RED))
	assert_true(spaced.has(Vector2i(7, 0)), "a space is three pixels: I(3) + gap(1) + space(3)")
	var odd := _covered(LFPixelDraw.text(_root, "~", 0, 0, 1, RED))
	var question := _covered(LFPixelDraw.text(_root, "?", 0, 0, 1, RED))
	assert_eq(odd, question)


func test_text_newline_starts_a_lower_line() -> void:
	var cells := _covered(LFPixelDraw.text(_root, "I\nI", 0, 0, 1, RED))
	assert_true(cells.has(Vector2i(0, 6)), "the second line starts a glyph plus one pixel lower")


func test_text_width_matches_what_is_drawn() -> void:
	for sample in ["I", "II", "HELLO", "M W", "A\nBBB", "I ", "  I", "I  \nII", "~", "A~ ", "", " ", "   ", "\n"]:
		var cells := _covered(LFPixelDraw.text(_root, sample, 0, 0, 1, RED))
		var right := 0
		for cell in cells:
			right = maxi(right, cell.x + 1)
		assert_eq(LFPixelDraw.text_width(sample, 1.0), float(right), sample)
	assert_eq(LFPixelDraw.text_width("II", 3.0), (3 + 1 + 3) * 3.0)
	assert_eq(LFPixelDraw.text_width("", 2.0), 0.0)


func test_text_with_no_pixel_size_draws_nothing() -> void:
	assert_eq(_rects(LFPixelDraw.text(_root, "HI", 0, 0, 0.0, RED)).size(), 0)


func test_freeing_a_holder_removes_all_its_pieces() -> void:
	var holder := LFPixelDraw.pattern(_root, ["XXX"], RED)
	holder.free()
	assert_eq(_root.get_child_count(), 0)


func test_glyph_rows_is_case_blind_and_falls_back_to_question_mark() -> void:
	assert_eq(LFPixelDraw.glyph_rows("a"), LFPixelDraw.FONT["A"])
	assert_eq(LFPixelDraw.glyph_rows("~"), LFPixelDraw.FONT["?"])


func test_text_width_ignores_trailing_spaces_and_counts_leading_ones() -> void:
	assert_eq(LFPixelDraw.text_width("I ", 1.0), 3.0)
	assert_eq(LFPixelDraw.text_width("I   ", 2.0), 6.0)
	assert_eq(LFPixelDraw.text_width("  I", 1.0), 9.0)
	assert_eq(LFPixelDraw.text_width("   ", 1.0), 0.0)
	assert_eq(LFPixelDraw.text_width("I", 0.0), 0.0)
