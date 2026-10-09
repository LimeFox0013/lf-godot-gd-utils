extends GutTest

## A 30-unit half-extent with 3-unit cells: a 20x20 grid. Cell (cx, cz) is centred at
## (-28.5 + 3 cx, -28.5 + 3 cz).
const HALF := 30.0
const CELL := 3.0
const SIZE := 20


func _center(cx: int, cz: int) -> Vector3:
	return LFGrid2D.cell_center(cx, cz, HALF, CELL)


## An open, flat 20x20 nav grid; `walls` lists blocked cells, `heights` maps cells to
## ground heights.
func _grid(walls: Array[Vector2i] = [], heights: Dictionary = {}) -> Dictionary:
	var blocked: Array[bool] = []
	var ground: Array[float] = []
	blocked.resize(SIZE * SIZE)
	ground.resize(SIZE * SIZE)
	for cell in walls:
		blocked[LFGrid2D.index_of(cell, SIZE)] = true
	for cell in heights:
		ground[LFGrid2D.index_of(cell, SIZE)] = heights[cell]
	return {'cols': SIZE, 'rows': SIZE, 'blocked': blocked, 'heights': ground}


func _column(cx: int, from_cz: int, to_cz: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cz in range(from_cz, to_cz + 1):
		cells.append(Vector2i(cx, cz))
	return cells


func _row(cz: int, from_cx: int, to_cx: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cx in range(from_cx, to_cx + 1):
		cells.append(Vector2i(cx, cz))
	return cells


## Follows the field from `start` in 1-unit steps; where it ends up.
func _walk(field: LFFlowField.Field, start: Vector3, steps := 200) -> Vector3:
	var position := start
	for i in steps:
		var direction := field.sample(position)
		if direction == Vector3.ZERO:
			break
		position += direction
	return position


func _cell_of(position: Vector3) -> Vector2i:
	return LFGrid2D.cell_of(position, HALF, CELL, SIZE, SIZE)


func test_with_no_density_the_direction_points_roughly_straight_at_the_goal():
	var goal := Vector3(20, 0, 0)
	var field := LFFlowField.compute(goal, HALF, CELL, [])
	var start := Vector3(-10, 0, 5)
	assert_gt(field.sample(start).dot((goal - start).normalized()), 0.7)


func test_a_dense_cluster_directly_ahead_bends_the_direction_away_from_the_straight_line():
	var goal := Vector3(30, 0, 0)
	var start := Vector3(-20, 0, 0)
	var wall: Array[Vector3] = []
	for x in range(-18, 10, 2):
		for i in 60:
			wall.append(Vector3(x, 0, 0))
	var calm := LFFlowField.compute(goal, 40.0, 2.0, [])
	var crowded := LFFlowField.compute(goal, 40.0, 2.0, wall)
	var toward := (goal - start).normalized()
	assert_lt(crowded.sample(start).dot(toward), calm.sample(start).dot(toward), 'routing round the crowd points less straight at the goal')
	assert_gt(absf(crowded.sample(start).z), 0.0, 'it diverts sideways')


func test_a_crowd_leaves_no_cell_without_a_way_forward():
	var crowd: Array[Vector3] = []
	for x in range(-18, 10, 2):
		for i in 60:
			crowd.append(Vector3(x, 0, 0))
	var goal := Vector3(30, 0, 0)
	var field := LFFlowField.compute(goal, 40.0, 2.0, crowd)
	var stuck := 0
	for cz in field.rows:
		for cx in field.cols:
			var center := LFGrid2D.cell_center(cx, cz, 40.0, 2.0)
			var direction := field.sample(center)
			var toward := Vector3(goal.x - center.x, 0, goal.z - center.z).normalized()
			# A cell pointing straight at the goal through the crowd found no cheaper neighbor.
			if direction.is_equal_approx(toward) and absf(center.z) < 4.0 and center.x < 10.0 and center.x > -20.0:
				stuck += 1
	assert_eq(stuck, 0, 'density is part of the path cost, so in front of a pile-up there is always a cheaper way round')


func test_crowd_positions_may_be_a_packed_array():
	var packed := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var plain: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0)]
	var a := LFFlowField.compute(Vector3(20, 0, 0), HALF, CELL, packed)
	var b := LFFlowField.compute(Vector3(20, 0, 0), HALF, CELL, plain)
	assert_eq(a.directions, b.directions)


func test_sampling_outside_the_grid_clamps():
	var field := LFFlowField.compute(Vector3.ZERO, 10.0, 2.0)
	assert_eq(field.sample(Vector3(1000, 0, -1000)), field.sample(Vector3(9.9, 0, -9.9)))


func test_a_cell_centred_on_the_goal_has_no_direction():
	var goal := Vector3(1, 0, 1)
	assert_eq(LFFlowField.compute(goal, 10.0, 2.0).sample(goal), Vector3.ZERO)


func test_a_field_is_a_packed_direction_per_cell():
	var field := LFFlowField.compute(Vector3(5, 0, 5), HALF, CELL)
	assert_eq(field.cols, SIZE)
	assert_eq(field.rows, SIZE)
	assert_eq(field.directions.size(), SIZE * SIZE)
	assert_eq(LFFlowField.sample_direction(field, Vector3(-20, 0, 3)), field.sample(Vector3(-20, 0, 3)))


func test_no_field_samples_as_zero():
	assert_eq(LFFlowField.sample_direction(null, Vector3.ONE), Vector3.ZERO)


func test_a_non_positive_cell_size_gives_an_empty_field():
	var field := LFFlowField.compute(Vector3.ZERO, HALF, 0.0)
	assert_push_error('cell_size')
	assert_eq(field.directions.size(), 0)
	assert_eq(field.sample(Vector3.ONE), Vector3.ZERO)


func test_a_non_finite_half_extent_gives_an_empty_field():
	var field := LFFlowField.compute(Vector3.ZERO, INF, 3.0)
	assert_push_error('half_extent')
	assert_eq(field.cols, 0)
	assert_true(field.directions.is_empty())
	assert_eq(LFFlowField.prepare_ground(NAN, 3.0).cols, 0)
	assert_push_error('half_extent')


func test_on_open_ground_every_direction_is_a_grid_step_or_an_even_blend():
	var field := LFFlowField.compute(Vector3(30, 0, 9), 60.0, 3.0)
	for start in [Vector3(-30, 0, 0), Vector3(-15, 0, -24), Vector3(0, 0, 30)]:
		var direction := field.sample(start)
		assert_almost_eq(direction.length(), 1.0, 0.0001)
		var angle := rad_to_deg(atan2(direction.z, direction.x))
		assert_almost_eq(fposmod(angle, 22.5), 0.0, 0.01, 'a multiple of 22.5° from %s' % start)


func test_a_field_toward_the_origin_mirrors_across_both_axes():
	var field := LFFlowField.compute(Vector3.ZERO, 60.0, 3.0)
	var mismatches := 0
	for i in range(-19, 20):
		for k in range(-19, 20):
			var p := Vector3(i * 3.0 + 0.1, 0, k * 3.0 + 0.1)
			var d := field.sample(p)
			if !field.sample(Vector3(-p.x, 0, p.z)).is_equal_approx(Vector3(-d.x, 0, d.z)):
				mismatches += 1
			if !field.sample(Vector3(p.x, 0, -p.z)).is_equal_approx(Vector3(d.x, 0, -d.z)):
				mismatches += 1
	assert_eq(mismatches, 0)


func test_a_wall_between_start_and_goal_is_routed_around():
	# A wall at cx 10 from the south edge up to cz 13; open above.
	var field := LFFlowField.compute(_center(15, 5), HALF, CELL, [], 0.0, _grid(_column(10, 0, 13)))
	assert_gt(field.sample(_center(8, 5)).z, 0.3, 'heads for the open end, not east into the wall')
	assert_eq(_cell_of(_walk(field, _center(8, 5))), Vector2i(15, 5), 'and gets there')


func test_no_direction_ever_steps_into_a_wall_even_when_two_ways_round_tie():
	# A wall at cx 10, cz 7..13, symmetric about the goal's row: north and south round it
	# cost the same from (8, 10).
	var walls := _column(10, 7, 13)
	var grid := _grid(walls)
	var field := LFFlowField.compute(_center(16, 10), HALF, CELL, [], 0.0, grid)
	for cz in SIZE:
		for cx in SIZE:
			if walls.has(Vector2i(cx, cz)):
				continue
			var direction := field.sample(_center(cx, cz))
			var heading := roundi(atan2(direction.z, direction.x) / (PI / 4.0))
			var step := Vector2i(roundi(cos(heading * PI / 4.0)), roundi(sin(heading * PI / 4.0)))
			assert_false(walls.has(Vector2i(cx, cz) + step), 'from %s the step %s enters the wall' % [Vector2i(cx, cz), step])
	assert_eq(_cell_of(_walk(field, _center(8, 10))), Vector2i(16, 10))


func test_climbing_is_limited_but_stepping_down_never_is():
	# A plateau 3 high east of cx 10, with a ramp (1, 2) along its south edge at cz 2..3.
	var heights := {}
	for cz in SIZE:
		for cx in range(10, SIZE):
			heights[Vector2i(cx, cz)] = 3.0
	for cz in [2, 3]:
		heights[Vector2i(8, cz)] = 1.0
		heights[Vector2i(9, cz)] = 2.0
	var grid := _grid([], heights)
	grid['max_climb'] = 1.5
	var up := LFFlowField.compute(_center(15, 15), HALF, CELL, [], 0.0, grid)
	assert_lt(up.sample(_center(6, 15)).z, -0.3, 'sent south toward the ramp, not east up the face')
	var down := LFFlowField.compute(_center(4, 15), HALF, CELL, [], 0.0, grid)
	assert_lt(down.sample(_center(13, 15)).x, -0.9, 'drops straight off the edge')


func test_without_a_climb_limit_any_rise_is_walkable():
	var heights := {}
	for cz in SIZE:
		for cx in range(10, SIZE):
			heights[Vector2i(cx, cz)] = 3.0
	var field := LFFlowField.compute(_center(15, 15), HALF, CELL, [], 0.0, _grid([], heights))
	assert_gt(field.sample(_center(6, 15)).x, 0.9)


func test_a_cleared_climbable_bit_forbids_that_step():
	var grid := _grid()
	var climbable: Array[int] = []
	climbable.resize(SIZE * SIZE)
	climbable.fill(511)
	# No cell of column 9 between cz 5 and 15 may step east (or diagonally east).
	for cz in range(5, 16):
		var mask := 511
		for offset in [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
			mask &= ~(1 << LFGrid2D.neighbor_bit(offset))
		climbable[LFGrid2D.index_of(Vector2i(9, cz), SIZE)] = mask
	grid['climbable'] = climbable
	var field := LFFlowField.compute(_center(15, 10), HALF, CELL, [], 0.0, grid)
	var direction := field.sample(_center(9, 10))
	assert_lt(direction.x, 0.5, 'never east out of column 9')


func test_a_diagonal_never_cuts_past_a_blocked_corner():
	var field := LFFlowField.compute(_center(11, 11), HALF, CELL, [], 0.0, _grid([Vector2i(11, 10)]))
	var direction := field.sample(_center(10, 10))
	assert_false(direction.is_equal_approx(Vector3(1, 0, 1).normalized()), 'not diagonally past the corner at (11, 10)')


func test_an_unreachable_cell_points_straight_at_the_goal():
	var walls: Array[Vector2i] = []
	walls.append_array(_row(7, 7, 12))
	walls.append_array(_row(12, 7, 12))
	walls.append_array(_column(7, 8, 11))
	walls.append_array(_column(12, 8, 11))
	var goal := _center(10, 10)
	var field := LFFlowField.compute(goal, HALF, CELL, [], 0.0, _grid(walls))
	var start := _center(2, 10)
	assert_true(field.sample(start).is_equal_approx(Vector3(goal.x - start.x, 0, goal.z - start.z).normalized()))


func test_a_body_inside_a_walls_cell_heads_out_to_open_ground_not_through_it():
	# Wall rows cz 7..8 from cx 0 to 15; the goal is south of them, the way round is east.
	var walls: Array[Vector2i] = []
	walls.append_array(_row(7, 0, 15))
	walls.append_array(_row(8, 0, 15))
	var field := LFFlowField.compute(_center(5, 2), HALF, CELL, [], 0.0, _grid(walls))
	assert_gt(field.sample(_center(5, 8)).z, 0.5, 'back out north, the open side')


func test_a_goal_inside_a_wall_routes_to_the_open_cells_beside_it():
	var walls := _column(10, 0, 15)
	var field := LFFlowField.compute(_center(10, 5), HALF, CELL, [], 0.0, _grid(walls))
	var end := _cell_of(_walk(field, _center(2, 18)))
	assert_eq(absi(end.x - 10), 1, 'ends beside the wall')
	assert_lt(absi(end.y - 5), 2, 'next to the goal')


func test_a_nav_grid_of_the_wrong_size_is_reported_and_ignored():
	var field := LFFlowField.compute(Vector3(15, 0, 0), 60.0, 3.0, [], 0.0, _grid(_column(10, 0, 19)))
	assert_push_error('does not match')
	assert_gt(field.sample(Vector3(-6, 0, 0)).x, 0.5, 'open-ground routing, not deflected by the wall')


func test_a_nav_grid_with_short_arrays_is_reported_and_ignored():
	var grid := _grid()
	grid['blocked'] = [true]
	var field := LFFlowField.compute(Vector3(15, 0, 0), HALF, CELL, [], 0.0, grid)
	assert_push_error('entries')
	assert_gt(field.sample(Vector3(-6, 0, 0)).x, 0.9)


func test_a_nav_grid_may_use_packed_arrays():
	var grid := _grid(_column(10, 0, 13))
	var packed := grid.duplicate()
	packed['blocked'] = PackedByteArray(grid['blocked'].map(func(b): return 1 if b else 0))
	packed['heights'] = PackedFloat32Array(grid['heights'])
	var a := LFFlowField.compute(_center(15, 5), HALF, CELL, [], 0.0, grid)
	var b := LFFlowField.compute(_center(15, 5), HALF, CELL, [], 0.0, packed)
	assert_eq(a.directions, b.directions)


func test_a_compute_asked_to_stop_returns_an_empty_field():
	var field := LFFlowField.compute(Vector3(5, 0, 5), HALF, CELL, [], 2.0, {}, func(): return true)
	assert_eq(field.directions.size(), 0)
	assert_eq(field.sample(Vector3.ZERO), Vector3.ZERO)


## A square height lattice over [-HALF, HALF] (SIZE cells of CELL), one sample per unit.
func _lattice(height: Callable) -> PackedFloat32Array:
	var samples := int(round(2.0 * HALF)) + 1
	var lattice := PackedFloat32Array()
	lattice.resize(samples * samples)
	for iz in samples:
		for ix in samples:
			lattice[iz * samples + ix] = height.call(-HALF + ix, -HALF + iz)
	return lattice


func _bit(offset: Vector2i) -> int:
	return 1 << LFGrid2D.neighbor_bit(offset)


func test_on_flat_ground_every_neighbor_is_climbable():
	var masks := LFFlowField.climbable_masks(_lattice(func(_x, _z): return 0.0), 1.0, HALF, CELL, 30.0)
	assert_eq(masks.size(), SIZE * SIZE)
	var all := 0
	for offset in LFGrid2D.NEIGHBORS_8:
		all |= _bit(offset)
	for mask in masks:
		assert_eq(mask, all)


func test_a_cliff_cannot_be_climbed_but_can_be_stepped_down():
	# Ground rises by 3 at x = 0 (the line between cells 9 and 10).
	var masks := LFFlowField.climbable_masks(_lattice(func(x, _z): return 3.0 if x >= 0.0 else 0.0), 1.0, HALF, CELL, 30.0)
	var below := LFGrid2D.index_of(Vector2i(9, 10), SIZE)
	var above := LFGrid2D.index_of(Vector2i(10, 10), SIZE)
	assert_eq(masks[below] & _bit(Vector2i(1, 0)), 0, 'not up the cliff')
	assert_ne(masks[above] & _bit(Vector2i(-1, 0)), 0, 'down it is fine')
	assert_ne(masks[below] & _bit(Vector2i(0, 1)), 0, 'along its foot is fine')


func test_a_gentle_ramp_is_climbable_and_a_steep_one_is_not():
	var gentle := LFFlowField.climbable_masks(_lattice(func(x, _z): return x * 0.2), 1.0, HALF, CELL, 30.0)
	var steep := LFFlowField.climbable_masks(_lattice(func(x, _z): return x * 0.8), 1.0, HALF, CELL, 30.0)
	var cell := LFGrid2D.index_of(Vector2i(10, 10), SIZE)
	assert_ne(gentle[cell] & _bit(Vector2i(1, 0)), 0, '~11° is walkable')
	assert_eq(steep[cell] & _bit(Vector2i(1, 0)), 0, '~39° is past 30°')
	assert_ne(steep[cell] & _bit(Vector2i(-1, 0)), 0, 'and still walkable downhill')


func test_a_lattice_of_the_wrong_size_is_reported_and_reads_as_open():
	var masks := LFFlowField.climbable_masks(PackedFloat32Array([0.0, 1.0]), 1.0, HALF, CELL, 30.0)
	assert_push_error('lattice')
	assert_eq(masks.size(), SIZE * SIZE)
	assert_eq(masks[LFGrid2D.index_of(Vector2i(10, 10), SIZE)] & _bit(Vector2i(1, 0)), _bit(Vector2i(1, 0)), 'every step allowed')


func test_a_zero_density_weight_reproduces_the_open_ground_field():
	var crowd: Array[Vector3] = []
	for i in 40:
		crowd.append(Vector3(0, 0, 0))
	var goal := Vector3(20, 0, 0)
	var open := LFFlowField.compute(goal, 30.0, 3.0)
	assert_eq(LFFlowField.compute(goal, 30.0, 3.0, crowd, 0.0).directions, open.directions)
	assert_ne(LFFlowField.compute(goal, 30.0, 3.0, crowd).directions, open.directions, 'the default weight bends round the crowd')


func test_a_negative_or_non_finite_density_weight_counts_as_zero():
	var crowd: Array[Vector3] = []
	for i in 40:
		crowd.append(Vector3(0, 0, 0))
	var goal := Vector3(20, 0, 0)
	var open := LFFlowField.compute(goal, 30.0, 3.0)
	for weight in [-5.0, NAN, INF]:
		var field := LFFlowField.compute(goal, 30.0, 3.0, crowd, weight)
		assert_eq(field.directions, open.directions, 'weight %s' % weight)


func test_a_goal_far_off_the_grid_is_routed_to_the_edge_nearest_it():
	# The same wall as above; the goal lies far east of the grid, level with row 5.
	var goal := Vector3(1000, 0, _center(15, 5).z)
	var field := LFFlowField.compute(goal, HALF, CELL, [], 0.0, _grid(_column(10, 0, 13)))
	assert_gt(field.sample(_center(8, 5)).z, 0.3, 'round the wall, not straight at it')
	assert_eq(_cell_of(_walk(field, _center(8, 5))), Vector2i(SIZE - 1, 5))


func test_a_field_records_the_goal_and_grid_it_was_computed_for():
	var goal := Vector3(5, 0, -4)
	var field := LFFlowField.compute(goal, HALF, CELL)
	assert_eq(field.goal, goal)
	assert_eq(field.half_extent, HALF)
	assert_eq(field.cell_size, CELL)


func test_a_non_finite_goal_is_reported_and_gives_an_empty_field():
	var field := LFFlowField.compute(Vector3(NAN, 0, 0), HALF, CELL)
	assert_push_error('finite')
	assert_eq(field.directions.size(), 0)
	assert_eq(field.sample(Vector3.ONE), Vector3.ZERO)


func test_a_goal_walled_in_routes_to_the_nearest_open_cells_however_far():
	# Only the two cells of the far corner are open: (8, 9) is nearer the goal at (0, 0).
	var blocked := PackedByteArray()
	blocked.resize(100)
	blocked.fill(1)
	blocked[98] = 0
	blocked[99] = 0
	var heights := PackedFloat32Array()
	heights.resize(100)
	var grid := {'cols': 10, 'rows': 10, 'blocked': blocked, 'heights': heights}
	var field := LFFlowField.compute(Vector3(-10, 0, -10), 10.0, 2.0, [], 0.0, grid)
	assert_eq(field.directions[99], Vector3(-1, 0, 0), 'toward the open cell nearest the goal, not straight at the goal')


func test_climbable_masks_may_come_in_any_numeric_array():
	var plain := _grid()
	var masks: Array[int] = []
	masks.resize(SIZE * SIZE)
	masks.fill(511)
	plain['climbable'] = masks
	var expected := LFFlowField.compute(_center(15, 10), HALF, CELL, [], 0.0, plain).directions
	for packed in [PackedInt32Array(masks), PackedInt64Array(masks), PackedFloat32Array(masks)]:
		var grid := plain.duplicate()
		grid['climbable'] = packed
		assert_eq(LFFlowField.compute(_center(15, 10), HALF, CELL, [], 0.0, grid).directions, expected, type_string(typeof(packed)))


func test_the_default_density_weight_is_the_documented_constant() -> void:
	var crowd := [Vector3(1.5, 0, 0), Vector3(1.5, 0, 0), Vector3(1.5, 0, 0)]
	var by_default := LFFlowField.compute(Vector3(6, 0, 0), 9.0, 3.0, crowd)
	var explicit := LFFlowField.compute(Vector3(6, 0, 0), 9.0, 3.0, crowd, LFFlowField.DEFAULT_DENSITY_WEIGHT)

	assert_eq(by_default.directions, explicit.directions)
	assert_eq(LFFlowFieldService.new(9.0).density_weight, LFFlowField.DEFAULT_DENSITY_WEIGHT)


func test_a_climbable_array_of_the_wrong_length_is_reported_and_the_grid_ignored():
	var grid := _grid(_column(10, 0, 19))
	grid['climbable'] = PackedInt32Array([511])
	var field := LFFlowField.compute(_center(15, 10), HALF, CELL, [], 0.0, grid)
	assert_push_error('`climbable` needs')
	assert_gt(field.sample(_center(5, 10)).x, 0.9, 'open-ground routing straight through the ignored wall')


func test_a_nav_grid_entry_that_is_not_an_array_is_reported_and_ignored():
	var grid := _grid()
	grid['heights'] = 'flat'
	var field := LFFlowField.compute(Vector3(15, 0, 0), HALF, CELL, [], 0.0, grid)
	assert_push_error('entries')
	assert_eq(field.directions.size(), SIZE * SIZE)


func test_a_grid_with_no_open_cell_points_every_cell_straight_at_the_goal():
	var blocked := PackedByteArray()
	blocked.resize(16)
	blocked.fill(1)
	var heights := PackedFloat32Array()
	heights.resize(16)
	var goal := Vector3(3, 0, 3)
	var field := LFFlowField.compute(goal, 4.0, 2.0, [], 0.0, {'cols': 4, 'rows': 4, 'blocked': blocked, 'heights': heights})
	assert_eq(field.directions.size(), 16)
	var center := LFGrid2D.cell_center(0, 0, 4.0, 2.0)
	assert_true(field.directions[0].is_equal_approx(Vector3(goal.x - center.x, 0, goal.z - center.z).normalized()))
	assert_eq(field.directions[15], Vector3.ZERO, 'the goal cell centre is the goal')


func test_a_stop_asked_partway_through_the_search_gives_an_empty_field():
	# A 20x20 grid settles 400 cells, so the search polls again after its first 256.
	var polls := [0]
	var stop_on_second_poll := func() -> bool:
		polls[0] += 1
		return polls[0] >= 2
	var field := LFFlowField.compute(Vector3(5, 0, 5), HALF, CELL, [], 2.0, {}, stop_on_second_poll)
	assert_eq(polls[0], 3, 'polled at the start, after 256 cells, and once more at the end')
	assert_eq(field.directions.size(), 0)


func test_a_stop_never_asked_gives_the_whole_field():
	var never := func() -> bool: return false
	var expected := LFFlowField.compute(Vector3(5, 0, 5), HALF, CELL)
	assert_eq(LFFlowField.compute(Vector3(5, 0, 5), HALF, CELL, [], 2.0, {}, never).directions, expected.directions)


func test_a_non_positive_lattice_spacing_is_reported_and_reads_as_open():
	var masks := LFFlowField.climbable_masks(_lattice(func(x, _z): return x * 5.0), 0.0, HALF, CELL, 30.0)
	assert_push_error('lattice')
	assert_eq(masks.size(), SIZE * SIZE)
	assert_ne(masks[LFGrid2D.index_of(Vector2i(10, 10), SIZE)] & _bit(Vector2i(1, 0)), 0, 'a steep ramp, yet every step allowed')


func test_crowd_positions_off_the_grid_count_in_the_nearest_edge_cell():
	# The goal sits in the east edge column; the crowd stands far east of the grid, a few
	# rows north of it, in the way of everyone coming down that column.
	var off_grid: Array[Vector3] = []
	var on_edge: Array[Vector3] = []
	for i in 40:
		off_grid.append(Vector3(1000, 0, -9))
		on_edge.append(Vector3(HALF - 0.1, 0, -9))
	var goal := _center(SIZE - 1, 10)
	var crowded := LFFlowField.compute(goal, HALF, CELL, off_grid)
	assert_eq(crowded.directions, LFFlowField.compute(goal, HALF, CELL, on_edge).directions)
	assert_ne(crowded.directions, LFFlowField.compute(goal, HALF, CELL).directions, 'the clamped crowd still bends the field')


## A ground prepared once gives every compute over it exactly the field reading the nav
## grid gives: walls (a body inside one included), a ledge, a climbing limit, a crowd.
func test_a_prepared_ground_gives_the_same_field_as_reading_the_nav_grid():
	var heights := {}
	for cz in SIZE:
		heights[Vector2i(14, cz)] = 2.0
	var grid := _grid(_column(9, 2, 17) + _row(4, 3, 8), heights)
	grid['max_climb'] = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var crowd := PackedVector3Array()
	for i in 200:
		crowd.append(Vector3(rng.randf_range(-HALF, HALF), 0, rng.randf_range(-HALF, HALF)))
	var ground := LFFlowField.prepare_ground(HALF, CELL, grid)
	for goal in [_center(17, 10), _center(9, 9), Vector3(-29, 0, 29)]:
		var read := LFFlowField.compute(goal, HALF, CELL, crowd, 2.0, grid)
		var prepared := LFFlowField.compute(goal, HALF, CELL, crowd, 2.0, {}, Callable(), ground)
		assert_true(prepared.directions == read.directions, 'goal %s' % goal)
	var open := LFFlowField.prepare_ground(HALF, CELL)
	assert_true(LFFlowField.compute(_center(3, 3), HALF, CELL, crowd, 2.0, {}, Callable(), open).directions
		== LFFlowField.compute(_center(3, 3), HALF, CELL, crowd).directions, 'open ground')


## A ground prepared for another grid size is reported, and the nav grid read instead.
func test_a_ground_prepared_for_another_grid_is_reported_and_the_nav_grid_read():
	var grid := _grid(_column(9, 0, 18))
	var wrong := LFFlowField.prepare_ground(HALF * 2.0, CELL)
	var field := LFFlowField.compute(_center(17, 10), HALF, CELL, [], 2.0, grid, Callable(), wrong)
	assert_push_error('prepared ground')
	assert_true(field.directions == LFFlowField.compute(_center(17, 10), HALF, CELL, [], 2.0, grid).directions)
