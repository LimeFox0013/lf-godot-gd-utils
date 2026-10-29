extends GutTest

const HALF := 30.0


func _terrain(features: Array[Dictionary]) -> LFTerrainFeatures:
	return LFTerrainFeatures.new(features)


func _platform() -> Array[Dictionary]:
	return [{ 'type': 'platform', 'rect': Rect2(-10, -10, 20, 20), 'height': 3.0 }]


func _ramp(low_edge: String) -> LFTerrainFeatures:
	return _terrain([{ 'type': 'ramp', 'rect': Rect2(0, 0, 10, 10), 'height': 4.0, 'low_edge': low_edge }])


func test_bare_ground_is_flat_open_and_walkable():
	var terrain := _terrain([])
	assert_eq(terrain.height_at(10.0, -20.0), 0.0)
	assert_false(terrain.is_wall_at(0.0, 0.0))
	assert_false(terrain.blocks_sight_between(Vector3(-10, 0, 0), Vector3(10, 0, 0)))
	assert_true(terrain.is_walkable_between(Vector3(-10, 0, 0), Vector3(10, 50, 0)))
	assert_false(terrain.has_elevation())


func test_a_platform_is_flat_and_inclusive_on_both_edges():
	var terrain := _terrain(_platform())
	assert_eq(terrain.height_at(0.0, 0.0), 3.0)
	assert_eq(terrain.height_at(10.0, 10.0), 3.0, 'the rect edge counts')
	assert_eq(terrain.height_at(-10.0, -10.0), 3.0)
	assert_eq(terrain.height_at(10.01, 0.0), 0.0)
	assert_true(terrain.has_elevation())


func test_a_ramp_rises_from_its_low_edge():
	assert_almost_eq(_ramp('x-').height_at(2.5, 5.0), 1.0, 0.0001)
	assert_almost_eq(_ramp('x+').height_at(2.5, 5.0), 3.0, 0.0001)
	assert_almost_eq(_ramp('z-').height_at(5.0, 7.5), 3.0, 0.0001)
	assert_almost_eq(_ramp('z+').height_at(5.0, 7.5), 1.0, 0.0001)


func test_a_hill_is_a_cosine_mound_that_ends_at_its_radius():
	var terrain := _terrain([{ 'type': 'hill', 'center': Vector2(0, 0), 'radius': 10.0, 'height': 2.0 }])
	assert_almost_eq(terrain.height_at(0.0, 0.0), 2.0, 0.0001)
	assert_almost_eq(terrain.height_at(5.0, 0.0), 1.0, 0.0001)
	assert_eq(terrain.height_at(10.0, 0.0), 0.0)
	assert_eq(terrain.height_at(12.0, 0.0), 0.0)


func test_overlapping_features_take_the_highest():
	var terrain := _terrain([
		{ 'type': 'platform', 'rect': Rect2(-10, -10, 20, 20), 'height': 3.0 },
		{ 'type': 'hill', 'center': Vector2(0, 0), 'radius': 5.0, 'height': 5.0 },
	])
	assert_almost_eq(terrain.height_at(0.0, 0.0), 5.0, 0.0001)
	assert_almost_eq(terrain.height_at(8.0, 0.0), 3.0, 0.0001)


func test_walls_and_foliage_are_listed_and_block_sight_but_only_walls_are_walls():
	var wall := { 'type': 'wall', 'rect': Rect2(-1, -5, 2, 10), 'height': 3.0 }
	var bush := { 'type': 'foliage', 'rect': Rect2(20, -5, 10, 10) }
	var terrain := _terrain([wall, bush])
	assert_eq(terrain.walls(), [wall])
	assert_eq(terrain.foliage(), [bush])
	assert_true(terrain.is_wall_at(1.0, 5.0), 'wall edge counts')
	assert_false(terrain.is_wall_at(25.0, 0.0))
	assert_true(terrain.blocks_sight_at(25.0, 0.0))
	assert_true(terrain.blocks_sight_between(Vector3(-5, 0, 0), Vector3(5, 0, 0)))
	assert_false(terrain.blocks_sight_between(Vector3(-5, 0, 8), Vector3(5, 0, 8)))
	assert_true(terrain.blocks_sight_between(Vector3(25, 0, 0), Vector3(15, 0, 0)), 'standing inside foliage')
	assert_true(terrain.blocks_sight_between(Vector3(15, 0, 0), Vector3(25, 0, 0)), 'and symmetrically')


func test_sight_step_decides_how_thin_a_blocker_can_be_missed():
	var features: Array[Dictionary] = [{ 'type': 'wall', 'rect': Rect2(4.9, -5, 0.2, 10), 'height': 3.0 }]
	var coarse := LFTerrainFeatures.new(features, LFTerrainFeatures.DEFAULT_MAX_SLOPE_DEG, 10.0)
	assert_false(coarse.blocks_sight_between(Vector3(0, 0, 0), Vector3(10, 0, 0)), 'one 10 unit step')
	var fine := LFTerrainFeatures.new(features, LFTerrainFeatures.DEFAULT_MAX_SLOPE_DEG, 0.1)
	assert_true(fine.blocks_sight_between(Vector3(0, 0, 0), Vector3(10, 0, 0)))


func test_walking_up_a_cliff_is_refused_a_ramp_allowed_and_dropping_off_fine():
	var terrain := _terrain([
		{ 'type': 'platform', 'rect': Rect2(0, -10, 10, 20), 'height': 3.0 },
		{ 'type': 'ramp', 'rect': Rect2(-12, -10, 12, 20), 'height': 3.0, 'low_edge': 'x-' },
	])
	assert_false(terrain.is_walkable_between(Vector3(5, 0, -20), Vector3(5, 3, 0)), 'up the cliff')
	assert_true(terrain.is_walkable_between(Vector3(-12, 0, 0), Vector3(5, 3, 0)), 'up the ramp')
	assert_true(terrain.is_walkable_between(Vector3(5, 3, 0), Vector3(5, 0, -20)), 'dropping off')


func test_max_slope_deg_is_a_parameter():
	var features: Array[Dictionary] = [{ 'type': 'ramp', 'rect': Rect2(0, -5, 10, 10), 'height': 5.0, 'low_edge': 'x-' }]
	assert_true(LFTerrainFeatures.new(features, 30.0).is_walkable_between(Vector3(0, 0, 0), Vector3(10, 5, 0)), 'a 27 degree ramp under 30')
	assert_false(LFTerrainFeatures.new(features, 20.0).is_walkable_between(Vector3(0, 0, 0), Vector3(10, 5, 0)))


func test_height_lattice_matches_height_at_on_every_sample():
	var terrain := _terrain([
		{ 'type': 'platform', 'rect': Rect2(-9, -9, 18, 18), 'height': 3.0 },
		{ 'type': 'ramp', 'rect': Rect2(9, -9, 12, 18), 'height': 3.0, 'low_edge': 'x+' },
		{ 'type': 'hill', 'center': Vector2(-20, 15), 'radius': 8.0, 'height': 2.5 },
	])
	var samples := int(2.0 * HALF) + 1
	var lattice := terrain.height_lattice(HALF, 1.0)
	assert_eq(lattice.size(), samples * samples)
	var mismatches := 0
	for iz in samples:
		for ix in samples:
			if lattice[iz * samples + ix] != PackedFloat32Array([terrain.height_at(-HALF + ix, -HALF + iz)])[0]:
				mismatches += 1
	assert_eq(mismatches, 0)


func test_a_flat_terrain_has_an_all_zero_lattice():
	var lattice := _terrain([]).height_lattice(HALF, 1.0)
	assert_eq(lattice.size(), 61 * 61)
	assert_eq(lattice.count(0.0), lattice.size())


func test_the_lattice_keeps_samples_exactly_on_a_rect_edge():
	var lattice := _terrain(_platform()).height_lattice(HALF, 1.0)
	assert_eq(lattice[40 * 61 + 40], 3.0, 'the far corner sample')
	assert_eq(lattice[20 * 61 + 20], 3.0, 'the near corner sample')
	assert_eq(lattice[41 * 61 + 40], 0.0, 'one sample past the edge')


func test_nav_grid_blocks_wall_cells_and_limits_climbing_with_elevation():
	var terrain := _terrain([
		{ 'type': 'wall', 'rect': Rect2(-1.5, -30, 3, 60), 'height': 3.0 },
		{ 'type': 'ramp', 'rect': Rect2(6, -6, 12, 12), 'height': 3.0, 'low_edge': 'x-' },
	])
	var grid := terrain.nav_grid(HALF, 3.0, 1.0)
	var cols := LFGrid2D.cells_across(HALF, 3.0)
	assert_eq(grid['cols'], cols)
	assert_true(grid['blocked'][LFGrid2D.index_of(Vector2i(9, 4), cols)])
	assert_false(grid['blocked'][LFGrid2D.index_of(Vector2i(14, 4), cols)])
	assert_almost_eq(grid['heights'][LFGrid2D.index_of(Vector2i(14, 10), cols)], terrain.height_at(LFGrid2D.cell_center(14, 10, HALF, 3.0).x, LFGrid2D.cell_center(14, 10, HALF, 3.0).z), 0.0001)
	var expected := LFFlowField.climbable_masks(terrain.height_lattice(HALF, 1.0), 1.0, HALF, 3.0, terrain.max_slope_deg)
	assert_eq(grid['climbable'], Array(expected))


func test_nav_grid_without_elevation_allows_every_step():
	var grid := _terrain([{ 'type': 'wall', 'rect': Rect2(0, 0, 3, 3), 'height': 3.0 }]).nav_grid(HALF, 3.0, 1.0)
	var all := 0
	for offset in LFGrid2D.NEIGHBORS_8:
		all |= 1 << LFGrid2D.neighbor_bit(offset)
	for mask in grid['climbable']:
		assert_eq(mask, all)


func test_assigning_features_sorts_them_out_again():
	var terrain := _terrain([])
	var first := terrain.walls()
	terrain.features = [{ 'type': 'wall', 'rect': Rect2(0, 0, 1, 1), 'height': 1.0 }]
	assert_eq(terrain.walls().size(), 1)
	assert_eq(first.size(), 0, 'a list handed out earlier is left alone')
	assert_true(terrain.is_wall_at(0.5, 0.5))


func test_a_feature_missing_keys_is_skipped_and_the_rest_still_work():
	var terrain := _terrain([
		{ 'type': 'ramp', 'rect': Rect2(0, 0, 10, 10), 'height': 4.0 },
		{ 'type': 'wall', 'height': 3.0 },
		{ 'type': 'hill', 'center': Vector2.ZERO, 'height': 2.0 },
		{ 'rect': Rect2(0, 0, 1, 1) },
		{ 'type': 'platform', 'rect': Rect2(20, 20, 5, 5), 'height': 2.0 },
	])
	assert_push_error_count(4)
	assert_eq(terrain.height_at(5.0, 5.0), 0.0)
	assert_eq(terrain.walls().size(), 0)
	assert_eq(terrain.height_at(22.0, 22.0), 2.0)


func test_a_zero_size_ramp_is_skipped_without_dividing_by_zero():
	var terrain := _terrain([
		{ 'type': 'ramp', 'rect': Rect2(0, 0, 0, 10), 'height': 4.0, 'low_edge': 'x-' },
		{ 'type': 'ramp', 'rect': Rect2(0, 0, 10, 0), 'height': 4.0, 'low_edge': 'z+' },
	])
	assert_push_error_count(2)
	assert_false(terrain.has_elevation())
	assert_eq(terrain.height_at(0.0, 0.0), 0.0)
	assert_eq(terrain.height_lattice(HALF, 1.0).size(), LFHeightmap.samples_for(HALF, 1.0) ** 2)


func test_a_ramp_with_an_unknown_low_edge_or_a_flat_hill_is_skipped():
	var terrain := _terrain([
		{ 'type': 'ramp', 'rect': Rect2(0, 0, 10, 10), 'height': 4.0, 'low_edge': 'up' },
		{ 'type': 'hill', 'center': Vector2.ZERO, 'radius': 0.0, 'height': 2.0 },
	])
	assert_push_error_count(2)
	assert_false(terrain.has_elevation())
