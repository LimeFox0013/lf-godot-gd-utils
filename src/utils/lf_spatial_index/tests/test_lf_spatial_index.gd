extends GutTest

var index: LFSpatialIndex
var near: Dictionary
var far: Dictionary


func before_each():
	index = LFSpatialIndex.new(4.0)
	near = {"name": "near"}
	far = {"name": "far"}
	index.register(near, Vector3(1, 0, 0))
	index.register(far, Vector3(100, 0, 0))


func test_query_radius_returns_only_objects_within_radius():
	var result = index.query_radius(Vector3.ZERO, 5.0)
	assert_true(result.has(near))
	assert_false(result.has(far))


func test_query_radius_excludes_objects_just_outside_it():
	var edge_object = {"name": "edge"}
	index.register(edge_object, Vector3(10.0, 0, 0))
	var result = index.query_radius(Vector3.ZERO, 5.0)
	assert_false(result.has(edge_object))


func test_query_radius_includes_an_object_exactly_on_the_boundary():
	var boundary_object = {"name": "boundary"}
	index.register(boundary_object, Vector3(5.0, 0, 0))
	var result = index.query_radius(Vector3.ZERO, 5.0)
	assert_true(result.has(boundary_object))


func test_update_position_moves_an_object_between_cells_without_reregistering():
	index.update_position(far, Vector3(0, 0, 0))
	var result = index.query_radius(Vector3.ZERO, 5.0)
	assert_true(result.has(far))
	# The far cell it used to occupy must no longer report it.
	assert_false(index.query_radius(Vector3(100, 0, 0), 1.0).has(far))


func test_remove_erases_the_object_from_the_cell_it_occupied():
	index.remove(near)
	var result = index.query_radius(Vector3.ZERO, 5.0)
	assert_false(result.has(near))


func test_remove_of_an_object_never_registered_is_a_no_op():
	var untracked = {"name": "ghost"}
	index.remove(untracked)
	assert_eq(index.query_radius(Vector3.ZERO, 5.0).size(), 1)


func test_clear_forgets_every_object():
	var a := Node.new()
	index.register(a, Vector3.ZERO)

	index.clear()

	assert_eq(index.query_radius(Vector3.ZERO, 10.0), [])
	assert_eq(index.size(), 0)
	a.free()


func test_cells_left_empty_by_moves_and_removals_are_dropped():
	var lone := LFSpatialIndex.new(4.0)
	var a := Node.new()
	lone.register(a, Vector3.ZERO)
	lone.update_position(a, Vector3(200, 0, 0))
	lone.remove(a)

	assert_eq(lone.cell_count(), 0, "a long-running index must not accumulate empty cells")
	a.free()


func test_changing_cell_size_keeps_queries_correct():
	var a := Node.new()
	index.register(a, Vector3(9, 0, 0))

	index.cell_size = 1.0

	assert_eq(index.query_radius(Vector3(9, 0, 0), 0.5), [a])
	a.free()


func test_positions_lists_every_registered_objects_current_position():
	index.update_position(far, Vector3(50, 0, 0))
	var all := Array(index.positions())
	all.sort()
	assert_eq(all, [Vector3(1, 0, 0), Vector3(50, 0, 0)])


func test_positions_drops_removed_objects():
	index.remove(near)
	assert_eq(index.positions(), PackedVector3Array([Vector3(100, 0, 0)]))


func test_registering_an_already_registered_object_moves_it_instead_of_duplicating_it():
	index.register(far, Vector3(0, 0, 0))

	assert_eq(index.query_radius(Vector3.ZERO, 5.0).count(far), 1, "the object must appear once, at its new position")
	assert_false(index.query_radius(Vector3(100, 0, 0), 1.0).has(far), "the old position must no longer report it")
	assert_eq(index.size(), 2, "re-registering must not add a second entry")
	assert_eq(index.position_of(far), Vector3.ZERO)


## A planar index buckets by X/Z only, yet still measures distance in 3D — the same
## answers as a full 3D index.
func test_a_planar_index_answers_like_a_3d_one():
	var flat := LFSpatialIndex.new(5.0, true)
	var full := LFSpatialIndex.new(5.0)
	var points := [Vector3(0, 0, 0), Vector3(3, 4, 0), Vector3(0, 9, 0), Vector3(-4, -2, 1), Vector3(12, 0, 0)]
	for i in points.size():
		flat.register(i, points[i])
		full.register(i, points[i])

	for radius in [1.0, 5.0, 8.0, 20.0]:
		var a := flat.query_radius(Vector3(0, 1, 0), radius)
		var b := full.query_radius(Vector3(0, 1, 0), radius)
		a.sort()
		b.sort()
		assert_eq(a, b, 'radius %s' % radius)


func test_positions_is_a_snapshot():
	var single := LFSpatialIndex.new()
	single.register("a", Vector3(1, 0, 0))
	var snapshot := single.positions()
	single.update_position("a", Vector3(9, 0, 0))
	assert_eq(snapshot, PackedVector3Array([Vector3(1, 0, 0)]), 'a later move never changes an earlier snapshot')


func test_switching_to_planar_on_a_populated_index_keeps_queries_correct():
	var lofty := LFSpatialIndex.new(4.0)
	lofty.register("a", Vector3(0, 10, 0))
	lofty.planar = true
	assert_eq(lofty.query_radius(Vector3(0, 10, 0), 1.0), ["a"])
	lofty.planar = false
	assert_eq(lofty.query_radius(Vector3(0, 10, 0), 1.0), ["a"])


func test_a_non_positive_cell_size_is_rejected_and_the_old_one_kept():
	index.cell_size = 0.0
	assert_push_error('cell_size')
	assert_eq(index.cell_size, 4.0)
	index.cell_size = -2.0
	assert_push_error('cell_size')
	assert_true(index.query_radius(Vector3.ZERO, 5.0).has(near))


func test_constructing_with_a_non_positive_cell_size_falls_back_to_the_default():
	var bad := LFSpatialIndex.new(-4.0)
	assert_push_error('cell_size')
	bad.register("a", Vector3(1, 0, 0))
	bad.register("b", Vector3(6, 0, 0))
	assert_eq(bad.query_radius(Vector3.ZERO, 10.0).size(), 2)


func test_cell_borders_at_negative_coordinates():
	var edge := {"name": "edge"}
	index.register(edge, Vector3(-4.0, 0, -4.0))
	assert_true(index.query_radius(Vector3(-4.0, 0, -4.0), 0.0).has(edge), 'exactly on a negative cell edge')
	assert_true(index.query_radius(Vector3(-3.9, 0, -3.9), 0.2).has(edge))
	assert_true(index.query_radius(Vector3(-4.1, 0, -4.1), 0.2).has(edge))


func test_update_position_registers_an_untracked_object():
	var fresh := {"name": "fresh"}
	index.update_position(fresh, Vector3(2, 0, 0))
	assert_true(index.has(fresh))
	assert_true(index.query_radius(Vector3.ZERO, 3.0).has(fresh))


func test_remove_then_register_again_tracks_it_once():
	index.remove(near)
	index.register(near, Vector3(2, 0, 0))
	var hits := index.query_radius(Vector3.ZERO, 5.0)
	assert_eq(hits.count(near), 1)


func test_position_of_and_has():
	assert_true(index.has(near))
	assert_eq(index.position_of(near), Vector3(1, 0, 0))
	index.update_position(near, Vector3(2, 0, 3))
	assert_eq(index.position_of(near), Vector3(2, 0, 3))
	index.remove(near)
	assert_false(index.has(near))
	assert_null(index.position_of(near))


func test_many_objects_in_one_cell_move_and_leave_without_mixing_positions():
	var crowd := LFSpatialIndex.new(10.0, true)
	for i in 6:
		crowd.register(i, Vector3(i, 0, 0))
	crowd.remove(1)
	crowd.update_position(3, Vector3(3, 0, 9))
	crowd.update_position(0, Vector3(50, 0, 0))
	for i in [2, 4, 5]:
		assert_eq(crowd.position_of(i), Vector3(i, 0, 0))
		assert_true(crowd.query_radius(Vector3(i, 0, 0), 0.1).has(i))
	assert_eq(crowd.query_radius(Vector3(3, 0, 9), 0.1), [3])
	assert_eq(crowd.query_radius(Vector3(50, 0, 0), 0.1), [0])
	assert_false(crowd.query_radius(Vector3(1, 0, 0), 0.5).has(1))


func test_a_freed_object_is_never_returned_and_is_forgotten():
	var node := Node.new()
	index.register(node, Vector3(1, 0, 1))
	node.free()
	var hits := index.query_radius(Vector3.ZERO, 5.0)
	assert_eq(hits, [near], 'the freed object is skipped')
	assert_false(index.has(node), 'and dropped from the index')


func test_each_query_returns_its_own_array():
	var first := index.query_radius(Vector3.ZERO, 5.0)
	var second := index.query_radius(Vector3(100, 0, 0), 5.0)
	assert_eq(first, [near], 'a later query never changes an earlier result')
	assert_eq(second, [far])


func test_a_query_can_also_hand_back_each_objects_position():
	var positions := PackedVector3Array([Vector3(9, 9, 9)])
	var hits := index.query_radius_positions(Vector3.ZERO, 5.0, positions)
	assert_eq(hits, [near])
	assert_eq(positions, PackedVector3Array([Vector3(1, 0, 0)]), 'filled in step with the objects, replacing what it held')


func test_a_positions_query_skips_freed_objects_in_both_lists():
	var node := Node.new()
	index.register(node, Vector3(2, 0, 0))
	node.free()
	var positions := PackedVector3Array()
	var hits := index.query_radius_positions(Vector3.ZERO, 5.0, positions)
	assert_eq(hits, [near])
	assert_eq(positions.size(), 1)
	assert_false(index.has(node), 'and the freed object is dropped from the index')


func test_a_negative_radius_finds_nothing():
	assert_eq(index.query_radius(Vector3(1, 0, 0), -1.0), [])
	assert_null(index.query_nearest(Vector3(1, 0, 0), -1.0))


func test_a_zero_radius_finds_only_an_object_exactly_there():
	assert_eq(index.query_radius(Vector3(1, 0, 0), 0.0), [near])
	assert_eq(index.query_radius(Vector3(1.5, 0, 0), 0.0), [])


func test_query_nearest_returns_the_nearest_not_the_first_found():
	var nearer := {"name": "nearer"}
	index.register(nearer, Vector3(0.5, 0, 0))
	index.register({"name": "behind"}, Vector3(-3, 0, 0))
	assert_eq(index.query_nearest(Vector3.ZERO, 5.0), nearer)
	assert_null(index.query_nearest(Vector3(50, 0, 0), 5.0), 'nothing in range')


func test_query_nearest_includes_the_boundary():
	assert_eq(index.query_nearest(Vector3(-4, 0, 0), 5.0), near)


func test_query_nearest_skips_exclude():
	assert_null(index.query_nearest(Vector3.ZERO, 5.0, Callable(), near))
	assert_eq(index.query_nearest(Vector3.ZERO, 5.0, Callable(), 'a key of another type'), near)


func test_query_nearest_asks_accept_only_about_improving_candidates():
	var mid := {"name": "mid"}
	var outer := {"name": "outer"}
	index.register(mid, Vector3(2, 0, 0))
	index.register(outer, Vector3(3, 0, 0))
	var asked: Array = []
	var accept := func(object):
		asked.append(object)
		return object != near
	# Several cells, so visiting order differs from distance order.
	var small := LFSpatialIndex.new(1.0)
	for object in [outer, mid, near]:
		small.register(object, index.position_of(object))
	assert_eq(small.query_nearest(Vector3.ZERO, 5.0, accept), mid)
	assert_eq(asked, [near, mid], 'never asked about the farther one once a nearer was accepted')

	# Registered first and lowest, so both a box scan and a walk over the occupied cells
	# meet it first.
	asked.clear()
	var spread := LFSpatialIndex.new(1.0)
	spread.register(near, Vector3(-4, 0, 0))
	spread.register(outer, Vector3(3, 0, 0))
	spread.register(mid, Vector3(2, 0, 0))
	assert_eq(spread.query_nearest(Vector3.ZERO, 5.0, accept), mid)
	assert_eq(asked.count(near), 1, 'the farther candidate visited first is asked once')


func test_query_nearest_hands_a_two_argument_accept_the_position():
	var seen: Array = []
	var accept := func(object, position):
		seen.append(position)
		return true
	assert_eq(index.query_nearest(Vector3.ZERO, 5.0, accept), near)
	assert_eq(seen, [Vector3(1, 0, 0)])


func test_query_nearest_forgets_a_freed_object():
	var node := Node.new()
	index.register(node, Vector3(0.1, 0, 0))
	node.free()
	assert_eq(index.query_nearest(Vector3.ZERO, 5.0), near)
	assert_false(index.has(node))


## The object count is process-wide (another test's worker thread may add or free a few
## meanwhile), so the bound is "fewer than one object per ten calls", which still fails if
## a call creates even one object that stays.
func test_query_nearest_allocates_nothing():
	var crowd := LFSpatialIndex.new(2.0, true)
	var nodes: Array[Node] = []
	for i in 50:
		var node := Node.new()
		nodes.append(node)
		crowd.register(node, Vector3(i % 10, 0, i / 10))
	var accept := func(object): return object != nodes[0]
	crowd.query_nearest(Vector3(5, 0, 2), 6.0, accept, nodes[1])
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 100:
		crowd.query_nearest(Vector3(5, 0, 2), 6.0, accept, nodes[1])
	assert_lt(Performance.get_monitor(Performance.OBJECT_COUNT) - before, 100 / 10.0, 'no object kept per call')
	for node in nodes:
		node.free()


func test_a_negative_radius_finds_nothing_even_within_one_cell():
	var flat := LFSpatialIndex.new(4.0, true)
	flat.register("a", Vector3(2, 0, 2))
	var positions := PackedVector3Array()
	assert_eq(flat.query_radius(Vector3(2, 0, 2), -0.5), [])
	assert_eq(flat.query_radius_positions(Vector3(2, 0, 2), -0.5, positions), [])
	assert_null(flat.query_nearest(Vector3(2, 0, 2), -0.5))


func test_a_huge_or_infinite_radius_is_clamped_to_the_occupied_cells():
	var started := Time.get_ticks_msec()
	for radius in [1e7, INF]:
		var hits := index.query_radius(Vector3.ZERO, radius)
		hits.sort_custom(func(a, b): return a.name < b.name)
		assert_eq(hits, [far, near], 'radius %s' % radius)
		var positions := PackedVector3Array()
		assert_eq(index.query_radius_positions(Vector3.ZERO, radius, positions).size(), 2)
		assert_eq(index.query_nearest(Vector3(90, 0, 0), radius), far)
	assert_lt(Time.get_ticks_msec() - started, 5000, 'scanning the empty cells of the box would take far longer')


func test_a_wide_planar_query_above_the_ground_still_finds_it():
	var flat := LFSpatialIndex.new(4.0, true)
	flat.register("a", Vector3(0, 0, 0))
	assert_eq(flat.query_radius(Vector3(0, 30, 0), 40.0), ["a"])
	assert_eq(flat.query_nearest(Vector3(0, 30, 0), 40.0), "a")


func test_a_wide_query_on_an_empty_index_finds_nothing():
	var empty := LFSpatialIndex.new(4.0)
	assert_eq(empty.query_radius(Vector3.ZERO, INF), [])
	assert_null(empty.query_nearest(Vector3.ZERO, INF))


func test_an_accept_that_queries_again_never_breaks_the_outer_query():
	var crowd := LFSpatialIndex.new(10.0, true)
	var node := Node.new()
	crowd.register('a', Vector3(1, 0, 0))
	crowd.register(node, Vector3(2, 0, 0))
	crowd.register('b', Vector3(3, 0, 0))
	crowd.register('c', Vector3(4, 0, 0))
	node.free()
	var seen: Array = []
	var accept := func(object, position):
		seen.append([object, position])
		crowd.query_radius(Vector3.ZERO, 100.0)  # meets the freed node in the same cell
		return true
	assert_eq(crowd.query_nearest(Vector3(5, 0, 0), 10.0, accept), 'c')
	for pair in seen:
		assert_eq(crowd.position_of(pair[0]), pair[1], 'each candidate came with its own position')
	assert_false(crowd.has(node), 'the freed node is still forgotten')


func test_an_object_at_a_nan_position_never_matches_a_query():
	# Flooring NaN to a cell is platform-defined (cell 0 on some CPUs), so the object may
	# sit in a scanned cell; its NaN distance must still never count as within range.
	var flat := LFSpatialIndex.new(4.0, true)
	flat.register("lost", Vector3(NAN, 0, NAN))
	flat.register("a", Vector3(1, 0, 0))
	var positions := PackedVector3Array()
	assert_eq(flat.query_radius(Vector3.ZERO, 5.0), ["a"])
	assert_eq(flat.query_radius_positions(Vector3.ZERO, 5.0, positions), ["a"])
	assert_eq(positions, PackedVector3Array([Vector3(1, 0, 0)]))
	assert_eq(flat.query_nearest(Vector3.ZERO, 5.0), "a")
	assert_eq(flat.query_nearest(Vector3.ZERO, 5.0, Callable(), "a"), null)


## A crowd spread over many cells, queried with radii small enough that the scan box is
## computed straight from the radius (not clamped to the occupied cells): every answer
## matches a brute-force scan.
func test_a_crowded_index_answers_like_a_brute_force_scan():
	for is_planar in [false, true]:
		var crowd := LFSpatialIndex.new(2.0, is_planar)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var points := {}
		for i in 600:
			points[i] = Vector3(rng.randf_range(-40, 40), rng.randf_range(-3, 3), rng.randf_range(-40, 40))
			crowd.register(i, points[i])
		assert_gt(crowd.cell_count(), 100, 'many occupied cells')
		for q in 30:
			var centre := Vector3(rng.randf_range(-40, 40), rng.randf_range(-3, 3), rng.randf_range(-40, 40))
			var radius := rng.randf_range(0.0, 5.0)
			var expected := []
			var nearest_distance := INF
			for i in points:
				var distance: float = points[i].distance_to(centre)
				if distance <= radius:
					expected.append(i)
					nearest_distance = minf(nearest_distance, distance)
			var hits := crowd.query_radius(centre, radius)
			hits.sort()
			assert_eq(hits, expected, 'planar %s, query %d' % [is_planar, q])
			var nearest: Variant = crowd.query_nearest(centre, radius)
			if expected.is_empty():
				assert_null(nearest)
			else:
				assert_almost_eq(points[nearest].distance_to(centre), nearest_distance, 0.0001)


func test_a_nan_radius_finds_nothing():
	var positions := PackedVector3Array()
	assert_eq(index.query_radius(Vector3(1, 0, 0), NAN), [])
	assert_eq(index.query_radius_positions(Vector3(1, 0, 0), NAN, positions), [])
	assert_null(index.query_nearest(Vector3(1, 0, 0), NAN))


func test_an_infinite_cell_size_is_rejected():
	index.cell_size = INF
	assert_push_error('cell_size')
	assert_eq(index.cell_size, 4.0)


func test_a_nan_cell_size_is_rejected():
	index.cell_size = NAN
	assert_push_error('cell_size')
	assert_eq(index.cell_size, 4.0)
	assert_true(index.query_radius(Vector3.ZERO, 5.0).has(near))


func test_of_equally_near_candidates_accept_is_asked_about_the_first_only():
	var tied := LFSpatialIndex.new(10.0)
	tied.register('left', Vector3(-1, 0, 0))
	tied.register('right', Vector3(1, 0, 0))
	var asked := []
	var accept := func(object):
		asked.append(object)
		return true
	var winner: Variant = tied.query_nearest(Vector3.ZERO, 5.0, accept)
	assert_eq(asked, [winner], 'a candidate only as near as the best is never asked about')


func test_query_nearest_returns_null_when_accept_takes_nothing():
	assert_null(index.query_nearest(Vector3.ZERO, 500.0, func(_object): return false))


func test_a_freed_object_moved_between_cells_is_still_forgotten():
	var node := Node.new()
	index.register(node, Vector3(1, 0, 1))
	index.update_position(node, Vector3(30, 0, 0))
	node.free()
	assert_eq(index.query_radius(Vector3(30, 0, 0), 1.0), [])
	assert_false(index.has(node))
	assert_eq(index.size(), 2)


## Objects spread far apart in small cells: a wide or infinite query walks the occupied
## cells (never the empty cells of its box) and still answers like a brute-force scan.
func test_a_wide_query_over_sparse_objects_walks_only_the_occupied_cells():
	for is_planar in [false, true]:
		var sparse := LFSpatialIndex.new(1.0, is_planar)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var points := {}
		for i in 300:
			points[i] = Vector3(rng.randf_range(-500, 500), rng.randf_range(0, 50), rng.randf_range(-500, 500))
			sparse.register(i, points[i])
		for radius in [40.0, 300.0, 1e7, INF]:
			var centre := Vector3(rng.randf_range(-100, 100), 10, rng.randf_range(-100, 100))
			var expected := []
			var nearest_distance := INF
			for i in points:
				var distance: float = points[i].distance_to(centre)
				if distance <= radius:
					expected.append(i)
					nearest_distance = minf(nearest_distance, distance)
			var hits := sparse.query_radius(centre, radius)
			assert_lte(sparse._last_scanned_cells, sparse.cell_count(), 'planar %s, radius %s: radius scan' % [is_planar, radius])
			hits.sort()
			assert_eq(hits, expected, 'planar %s, radius %s' % [is_planar, radius])
			var positions := PackedVector3Array()
			var with_positions := sparse.query_radius_positions(centre, radius, positions)
			for k in with_positions.size():
				assert_eq(positions[k], points[with_positions[k]])
			var nearest: Variant = sparse.query_nearest(centre, radius)
			assert_lte(sparse._last_scanned_cells, sparse.cell_count(), 'planar %s, radius %s: nearest scan' % [is_planar, radius])
			if expected.is_empty():
				assert_null(nearest)
			else:
				assert_almost_eq(points[nearest].distance_to(centre), nearest_distance, 0.0001)


## The box a wide query is clamped to follows the objects: once the far ones leave, it
## shrinks back to the cells still occupied instead of keeping their old reach.
func test_a_wide_query_box_shrinks_when_the_outermost_objects_leave():
	var crowd := LFSpatialIndex.new(1.0, true)
	for x in 4:
		for z in 4:
			crowd.register(Vector2i(x, z), Vector3(x, 0, z))
	crowd.register('far', Vector3(400, 0, 0))
	crowd.query_radius(Vector3.ZERO, INF)
	assert_eq(crowd._last_scanned_cells, crowd.cell_count(), 'objects far apart: walks the occupied cells')
	crowd.update_position('far', Vector3(2, 0, 2))
	assert_eq(crowd.query_radius(Vector3.ZERO, INF).size(), 17)
	assert_eq(crowd._last_scanned_cells, 16, 'the 4 x 4 cells left, not the box out to 400')
	crowd.remove('far')
	crowd.register('far', Vector3(-400, 0, 0))
	assert_eq(crowd.query_nearest(Vector3(-390, 0, 0), INF), 'far', 'and it grows again')


## A freed object met by a query run from inside `accept` is forgotten once the outer
## query ends, while live objects around it stay found.
func test_a_freed_object_met_by_a_nested_wide_query_is_forgotten_after_the_outer_one():
	var sparse := LFSpatialIndex.new(1.0)
	var node := Node.new()
	sparse.register('a', Vector3(1, 0, 0))
	sparse.register(node, Vector3(200, 0, 0))
	sparse.register('b', Vector3(-300, 0, 0))
	node.free()
	var inner_hits: Array = []
	var accept := func(_object):
		inner_hits.clear()
		inner_hits.append_array(sparse.query_radius(Vector3.ZERO, INF))
		assert_true(sparse.size() == 3, 'not forgotten while the outer query walks the cells')
		return true
	assert_eq(sparse.query_nearest(Vector3.ZERO, INF, accept), 'a')
	inner_hits.sort()
	assert_eq(inner_hits, ['a', 'b'])
	assert_eq(sparse.size(), 2, 'forgotten once the outer query ended')
