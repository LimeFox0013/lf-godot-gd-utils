extends GutTest

func test_cells_cover_the_square_and_centres_sit_inside_their_cells():
	assert_eq(LFGrid2D.cells_across(30.0, 3.0), 20)
	assert_eq(LFGrid2D.cells_across(10.0, 3.0), 7, 'a partial cell still counts')
	assert_eq(LFGrid2D.cell_center(0, 0, 30.0, 3.0), Vector3(-28.5, 0, -28.5))
	assert_eq(LFGrid2D.cell_of(LFGrid2D.cell_center(4, 9, 30.0, 3.0), 30.0, 3.0, 20, 20), Vector2i(4, 9))


func test_an_off_grid_position_names_its_nearest_edge_cell():
	assert_eq(LFGrid2D.cell_of(Vector3(-100, 0, 100), 30.0, 3.0, 20, 20), Vector2i(0, 19))


func test_every_neighbor_has_its_own_bit_and_the_cell_itself_is_the_middle():
	var bits := {}
	for offset in LFGrid2D.NEIGHBORS_8:
		bits[LFGrid2D.neighbor_bit(offset)] = true
	assert_eq(bits.size(), 8)
	assert_false(bits.has(4))
	assert_eq(LFGrid2D.neighbor_bit(Vector2i.ZERO), 4)


func test_float_rounding_never_adds_a_phantom_cell():
	assert_eq(LFGrid2D.cells_across(0.55, 0.1), 11)
	assert_eq(LFGrid2D.cells_across(0.35, 0.1), 7)


func test_a_non_positive_cell_size_is_reported_and_spans_nothing():
	assert_eq(LFGrid2D.cells_across(60.0, 0.0), 0)
	assert_push_error('cell_size')
	assert_eq(LFGrid2D.cells_across(60.0, -2.0), 0)
	assert_push_error('cell_size')


func test_a_non_finite_extent_is_reported_and_spans_nothing():
	assert_eq(LFGrid2D.cells_across(INF, 1.0), 0)
	assert_push_error('half_extent')
	assert_eq(LFGrid2D.cells_across(NAN, 1.0), 0)
	assert_push_error('half_extent')
	assert_eq(LFGrid2D.cells_overlapping(Rect2(0, 0, 1, 1), INF, 1.0), [] as Array[Vector2i])
	assert_push_error('half_extent')


func test_a_negative_extent_spans_nothing():
	assert_eq(LFGrid2D.cells_across(-5.0, 1.0), 0)


func test_index_of_is_row_major():
	assert_eq(LFGrid2D.index_of(Vector2i(0, 0), 20), 0)
	assert_eq(LFGrid2D.index_of(Vector2i(4, 9), 20), 9 * 20 + 4)


func test_in_bounds_accepts_exactly_the_grid():
	assert_true(LFGrid2D.in_bounds(Vector2i(0, 0), 3, 2))
	assert_true(LFGrid2D.in_bounds(Vector2i(2, 1), 3, 2))
	assert_false(LFGrid2D.in_bounds(Vector2i(3, 1), 3, 2))
	assert_false(LFGrid2D.in_bounds(Vector2i(0, 2), 3, 2))
	assert_false(LFGrid2D.in_bounds(Vector2i(-1, 0), 3, 2))


func test_step_lengths_follow_the_neighbor_order():
	assert_eq(LFGrid2D.NEIGHBOR_STEP_LENGTHS.size(), LFGrid2D.NEIGHBORS_8.size())
	for i in LFGrid2D.NEIGHBORS_8.size():
		assert_almost_eq(LFGrid2D.NEIGHBOR_STEP_LENGTHS[i], Vector2(LFGrid2D.NEIGHBORS_8[i]).length(), 1e-6)


func test_cells_overlapping_lists_every_cell_the_rect_covers():
	# A 4 x 4 grid of 1-unit cells over [-2, 2]; the rect covers parts of cells 1..2 on X and 0..1 on Z.
	var cells := LFGrid2D.cells_overlapping(Rect2(-0.5, -1.5, 1.0, 1.0), 2.0, 1.0)
	assert_eq(cells, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)] as Array[Vector2i])


func test_a_shared_edge_alone_does_not_overlap():
	# Exactly cell (2, 2): its edges touch cells 1 and 3 on each axis but cover none of them.
	var cells := LFGrid2D.cells_overlapping(Rect2(0.0, 0.0, 1.0, 1.0), 2.0, 1.0)
	assert_eq(cells, [Vector2i(2, 2)] as Array[Vector2i])


func test_cells_overlapping_never_leaves_the_grid():
	assert_eq(LFGrid2D.cells_overlapping(Rect2(1.5, 1.5, 10.0, 10.0), 2.0, 1.0), [Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(LFGrid2D.cells_overlapping(Rect2(5.0, 5.0, 1.0, 1.0), 2.0, 1.0), [] as Array[Vector2i], 'wholly off the grid')


func test_a_negative_size_rect_is_read_as_its_absolute_rect():
	assert_eq(LFGrid2D.cells_overlapping(Rect2(1.0, 1.0, -1.0, -1.0), 2.0, 1.0), [Vector2i(2, 2)] as Array[Vector2i])


func test_cells_overlapping_with_a_bad_cell_size_is_empty():
	assert_eq(LFGrid2D.cells_overlapping(Rect2(0, 0, 1, 1), 2.0, 0.0), [] as Array[Vector2i])
	assert_push_error('cell_size')


func test_a_nan_cell_size_is_reported_and_spans_nothing():
	assert_eq(LFGrid2D.cells_across(60.0, NAN), 0)
	assert_push_error('cell_size')
	assert_eq(LFGrid2D.cells_overlapping(Rect2(0, 0, 1, 1), 2.0, NAN), [] as Array[Vector2i])
	assert_push_error('cell_size')


func test_a_rect_wholly_off_the_low_side_of_the_grid_overlaps_nothing():
	# cell_of clamps the corners to cell (0, 0), which the rect still does not cover.
	assert_eq(LFGrid2D.cells_overlapping(Rect2(-10.0, -10.0, 1.0, 1.0), 2.0, 1.0), [] as Array[Vector2i])
	assert_eq(LFGrid2D.cells_overlapping(Rect2(-10.0, 0.25, 1.0, 0.5), 2.0, 1.0), [] as Array[Vector2i], 'off on X only')


func test_a_rect_over_a_partial_last_cell_reaches_it():
	# 2.5 / 1.0 is not whole: 5 cells over [-2.5, 2.5], the last one 1 unit wide but cut at the edge.
	assert_eq(LFGrid2D.cells_across(2.5, 1.0), 5)
	assert_eq(LFGrid2D.cells_overlapping(Rect2(2.2, 2.2, 5.0, 5.0), 2.5, 1.0), [Vector2i(4, 4)] as Array[Vector2i])


func test_a_position_just_below_a_cell_boundary_stays_in_the_lower_cell():
	# Cell 9 of a 20-cell, 3-unit grid spans [-3, 0) on X.
	assert_eq(LFGrid2D.cell_of(Vector3(-3.0001, 0, 0), 30.0, 3.0, 20, 20).x, 8)
	assert_eq(LFGrid2D.cell_of(Vector3(-3.0, 0, 0), 30.0, 3.0, 20, 20).x, 9)
