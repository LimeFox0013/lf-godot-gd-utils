extends GutTest

var _updates: Array[Vector2i] = []


func _on_field_updated(cell: Vector2i) -> void:
	_updates.append(cell)


func _wait_ready(service: LFFlowFieldService, goal: Vector3, max_frames := 300) -> void:
	for i in max_frames:
		service.tick(0.05)
		if service.field_for(goal) != null:
			return
		await get_tree().process_frame
	fail_test('no field within the polling budget')


func _wait_idle(service: LFFlowFieldService, max_frames := 300) -> void:
	for i in max_frames:
		service.tick(0.0)
		if service.pending_count() == 0:
			return
		await get_tree().process_frame
	fail_test('computes did not finish within the polling budget')


func before_each():
	_updates.clear()


func test_a_requested_field_becomes_ready_and_points_at_the_goal():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(20, 0, 0)
	assert_eq(service.direction(goal, Vector3.ZERO), Vector3.ZERO, 'nothing ready yet')
	service.field_updated.connect(_on_field_updated)
	service.request_field(goal)
	await _wait_ready(service, goal)
	assert_gt(service.direction(goal, Vector3.ZERO).x, 0.9)
	assert_eq(_updates, [service.cell_for(goal)])


func test_a_field_in_flight_is_never_started_twice():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(20, 0, 0)
	service.request_field(goal)
	service.tick(0.0)
	service.request_field(goal)
	service.tick(0.0)
	assert_eq(service.pending_count(), 1)
	assert_true(service.is_pending(goal))
	await _wait_ready(service, goal)


func test_goals_in_one_cell_share_a_field():
	var service := LFFlowFieldService.new(30.0, 3.0)
	service.request_field(Vector3(20.2, 0, 0.2))
	service.request_field(Vector3(20.8, 0, 0.9))
	service.tick(0.0)
	assert_eq(service.pending_count(), 1)
	await _wait_idle(service)


func test_the_shared_cell_is_the_fields_own_cell():
	# 61 / 3 is not whole: the grid starts at -61, so x = 1.0 and x = 2.9 are different cells.
	var service := LFFlowFieldService.new(61.0, 3.0)
	assert_ne(service.cell_for(Vector3(1.0, 0, 0)), service.cell_for(Vector3(2.9, 0, 0)))
	assert_eq(service.cell_for(Vector3(1.0, 0, 0)), LFGrid2D.cell_of(Vector3(1.0, 0, 0), 61.0, 3.0, 41, 41))


func test_prune_drops_fields_no_longer_wanted_and_keeps_the_rest():
	var service := LFFlowFieldService.new(30.0)
	var kept := Vector3(20, 0, 0)
	var dropped := Vector3(-20, 0, 0)
	service.request_field(kept)
	service.request_field(dropped)
	await _wait_ready(service, kept)
	await _wait_ready(service, dropped)
	service.prune([kept])
	assert_not_null(service.field_for(kept))
	assert_null(service.field_for(dropped))
	service.tick(5.0)
	assert_false(service.is_pending(dropped), 'never recomputed')
	await _wait_idle(service)


func test_new_ground_drops_ready_fields_and_recomputes_them_over_it():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(15, 0, 0)
	service.request_field(goal)
	await _wait_ready(service, goal)
	var blocked: Array[bool] = []
	blocked.resize(400)
	for cz in 20:
		blocked[cz * 20 + 10] = true
	var heights: Array[float] = []
	heights.resize(400)
	service.set_nav_grid({'cols': 20, 'rows': 20, 'blocked': blocked, 'heights': heights})
	assert_null(service.field_for(goal), 'the old field is gone at once')
	await _wait_ready(service, goal)
	assert_false(service.nav_grid.is_empty())


func test_a_compute_started_on_old_ground_is_thrown_away():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(15, 0, 0)
	service.field_updated.connect(_on_field_updated)
	service.request_field(goal)
	service.tick(0.0)
	assert_eq(service.pending_count(), 1)
	service.set_nav_grid({})
	await _wait_idle(service)
	assert_null(service.field_for(goal), 'the result computed before the change is never served')
	assert_eq(_updates, [] as Array[Vector2i])
	await _wait_ready(service, goal)
	assert_eq(_updates.size(), 1, 'the recompute on the new ground is')


func test_the_crowd_is_read_only_on_a_frame_that_starts_a_compute():
	var service := LFFlowFieldService.new(30.0)
	var reads := [0]
	var crowd := func():
		reads[0] += 1
		return [Vector3.ZERO]
	service.request_field(Vector3(10, 0, 0))
	service.tick(0.0, crowd)
	service.tick(0.0, crowd)
	assert_eq(reads[0], 1)
	await _wait_idle(service)


func test_at_most_max_concurrent_computes_run_at_once():
	var service := LFFlowFieldService.new(30.0)
	service.max_concurrent = 2
	for x in [-20, -10, 0, 10, 20]:
		service.request_field(Vector3(x, 0, 0))
	service.tick(0.0)
	assert_eq(service.pending_count(), 2)
	for x in [-20, -10, 0, 10, 20]:
		await _wait_ready(service, Vector3(x, 0, 0))
	assert_not_null(service.field_for(Vector3(20, 0, 0)), 'the rest start as slots free up')


func test_the_service_keeps_its_own_copy_of_the_ground():
	var service := LFFlowFieldService.new(30.0)
	var blocked: Array[bool] = []
	blocked.resize(400)
	var heights: Array[float] = []
	heights.resize(400)
	var grid := {'cols': 20, 'rows': 20, 'blocked': blocked, 'heights': heights}
	service.set_nav_grid(grid)
	grid['blocked'][0] = true
	grid.erase('heights')
	assert_false(service.nav_grid['blocked'][0])
	assert_true(service.nav_grid.has('heights'))


func test_a_compute_for_a_pruned_goal_is_never_published():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(15, 0, 0)
	service.field_updated.connect(_on_field_updated)
	service.request_field(goal)
	service.tick(0.0)
	service.prune([])
	await _wait_idle(service)
	assert_null(service.field_for(goal))
	assert_eq(_updates, [] as Array[Vector2i])


var _dropped: Array[Vector2i] = []


func _on_field_dropped(cell: Vector2i) -> void:
	_dropped.append(cell)


func test_dropping_a_ready_field_is_announced():
	_dropped.clear()
	var service := LFFlowFieldService.new(30.0)
	var pruned := Vector3(20, 0, 0)
	var regrounded := Vector3(-20, 0, 0)
	service.field_dropped.connect(_on_field_dropped)
	service.request_field(pruned)
	service.request_field(regrounded)
	await _wait_ready(service, pruned)
	await _wait_ready(service, regrounded)

	service.prune([regrounded])
	assert_eq(_dropped, [service.cell_for(pruned)], 'pruning drops the unwanted field')
	service.set_nav_grid({})
	assert_eq(_dropped, [service.cell_for(pruned), service.cell_for(regrounded)], 'new ground drops the rest')
	await _wait_idle(service)


func _crowd_across_the_middle() -> Array[Vector3]:
	var crowd: Array[Vector3] = []
	for z in range(-12, 13, 3):
		for i in 30:
			crowd.append(Vector3(0, 0, z))
	return crowd


func test_a_wanted_field_is_recomputed_every_interval_and_follows_the_crowd():
	var service := LFFlowFieldService.new(30.0, 3.0, 0.5)
	var goal := Vector3(20, 0, 0)
	service.field_updated.connect(_on_field_updated)
	service.request_field(goal)
	await _wait_ready(service, goal)
	var open_field := service.field_for(goal)
	assert_eq(_updates.size(), 1)

	service.tick(0.2, _crowd_across_the_middle())
	assert_false(service.is_pending(goal), 'not due before the interval')
	service.tick(0.3, _crowd_across_the_middle())
	assert_true(service.is_pending(goal), 'due once the interval has passed')
	for i in 300:
		if _updates.size() == 2:
			break
		service.tick(0.0)
		await get_tree().process_frame
	assert_eq(_updates.size(), 2, 'a second field arrived')
	var crowded_field := service.field_for(goal)
	assert_ne(crowded_field, open_field)
	assert_ne(crowded_field.directions, open_field.directions, 'the crowd bends the field')


func test_the_service_density_weight_reaches_the_compute():
	var crowd := _crowd_across_the_middle()
	var goal := Vector3(20, 0, 0)
	var open_ground := LFFlowField.compute(goal, 30.0, 3.0)
	var service := LFFlowFieldService.new(30.0, 3.0, 1.0, 0.0)
	service.request_field(goal)
	service.tick(0.0, crowd)
	await _wait_ready(service, goal)
	assert_eq(service.field_for(goal).directions, open_ground.directions, 'a zero weight ignores the crowd')

	var weighted := LFFlowFieldService.new(30.0, 3.0, 1.0, 5.0)
	weighted.request_field(goal)
	weighted.tick(0.0, crowd)
	await _wait_ready(weighted, goal)
	assert_ne(weighted.field_for(goal).directions, open_ground.directions)


func test_a_goal_pruned_mid_compute_and_wanted_again_never_reads_an_empty_field():
	var service := LFFlowFieldService.new(30.0)
	var goal := Vector3(15, 0, 0)
	service.request_field(goal)
	service.tick(0.0)
	service.prune([])
	service.request_field(goal)
	for i in 300:
		service.tick(0.0)
		var field := service.field_for(goal)
		if field != null:
			assert_false(field.directions.is_empty(), 'never the stopped compute\'s empty field')
			assert_gt(service.direction(goal, Vector3(-15, 0, 0)).x, 0.9)
			break
		await get_tree().process_frame
	assert_not_null(service.field_for(goal), 'the goal is computed again')
	await _wait_idle(service)


func test_the_grid_is_fixed_at_construction():
	var service := LFFlowFieldService.new(30.0, 3.0)
	var cell := service.cell_for(Vector3(7, 0, 7))
	service.half_extent = 60.0
	assert_push_error('half_extent')
	service.cell_size = 1.0
	assert_push_error('cell_size')
	assert_eq(service.half_extent, 30.0)
	assert_eq(service.cell_size, 3.0)
	assert_eq(service.cell_for(Vector3(7, 0, 7)), cell)


func test_the_constructor_sets_the_tunables_and_they_can_change_later():
	var service := LFFlowFieldService.new(30.0, 3.0, 0.5, 1.5)
	assert_eq(service.refresh_interval, 0.5)
	assert_eq(service.density_weight, 1.5)
	assert_eq(service.max_concurrent, 4)
	assert_eq(service.nav_grid, {})
	var goal := Vector3(10, 0, 0)
	service.request_field(goal)
	await _wait_ready(service, goal)
	service.refresh_interval = 10.0
	service.tick(1.0)
	assert_false(service.is_pending(goal), 'a longer interval applies from the next tick')
	service.tick(9.0)
	assert_true(service.is_pending(goal))
	await _wait_idle(service)


func test_a_non_positive_cell_size_is_reported_and_no_field_becomes_ready():
	var service := LFFlowFieldService.new(30.0, 0.0)
	assert_push_error('cell_size')
	var goal := Vector3(10, 0, 0)
	service.request_field(goal)
	for i in 20:
		service.tick(0.05)
		await get_tree().process_frame
	assert_eq(service.pending_count(), 0, 'no compute is ever started')
	assert_null(service.field_for(goal))
	assert_eq(service.direction(goal, Vector3.ZERO), Vector3.ZERO)
	await _wait_idle(service)


func test_a_non_finite_goal_is_reported_once_and_never_computed():
	var service := LFFlowFieldService.new(30.0, 3.0)
	service.request_field(Vector3(NAN, 0, 0))
	assert_push_error('finite')
	for i in 5:
		service.tick(2.0)
	assert_eq(service.pending_count(), 0)


func test_assigning_the_nav_grid_is_reported_and_ignored():
	var service := LFFlowFieldService.new(30.0, 3.0)
	service.set('nav_grid', {'cols': 20})
	assert_push_error('set_nav_grid')
	assert_eq(service.nav_grid, {})


func test_requesting_the_same_goal_again_does_not_force_a_recompute():
	var service := LFFlowFieldService.new(30.0, 3.0, 1.0)
	var goal := Vector3(20, 0, 0)
	service.request_field(goal)
	await _wait_ready(service, goal)
	await _wait_idle(service)
	service.request_field(goal)
	service.tick(0.0)
	assert_eq(service.pending_count(), 0, 'a repeated request waits for the refresh interval')
	service.request_field(Vector3(20.5, 0, 0.5)) # another goal in the same cell
	service.tick(0.0)
	assert_eq(service.pending_count(), 1, 'a changed goal is due at once')
	await _wait_idle(service)


func test_a_nan_or_negative_delta_adds_nothing():
	var service := LFFlowFieldService.new(30.0, 3.0, 1.0)
	var goal := Vector3(20, 0, 0)
	service.request_field(goal)
	await _wait_ready(service, goal)
	await _wait_idle(service)
	service.tick(NAN)
	service.tick(-5.0)
	assert_eq(service.pending_count(), 0)
	service.tick(1.0)
	assert_eq(service.pending_count(), 1, 'one refresh interval later the field recomputes')
	await _wait_idle(service)


## The ground is prepared once per `set_nav_grid`: every later compute shares it, and new
## ground is prepared again (a compute started on the old ground never hands its own in).
func test_the_ground_is_prepared_once_per_nav_grid_and_shared_by_later_computes():
	var service := LFFlowFieldService.new(30.0, 3.0, 0.1)
	var goal := Vector3(15, 0, 0)
	service.request_field(goal)
	await _wait_ready(service, goal)
	var first: LFFlowField.Ground = service._ground
	assert_not_null(first, 'prepared by the first compute')
	service.request_field(Vector3(-15, 0, 0))
	await _wait_ready(service, Vector3(-15, 0, 0))
	for i in 5:
		service.tick(0.2)
		await get_tree().process_frame
	await _wait_idle(service)
	assert_true(is_same(service._ground, first), 'recomputes and other goals reuse it')

	var blocked: Array[bool] = []
	blocked.resize(400)
	for cz in 20:
		blocked[cz * 20 + 15] = true
	var heights: Array[float] = []
	heights.resize(400)
	service.set_nav_grid({'cols': 20, 'rows': 20, 'blocked': blocked, 'heights': heights})
	assert_null(service._ground, 'dropped with the old ground')
	await _wait_ready(service, goal)
	await _wait_idle(service)
	assert_eq(service._ground.blocked[5 * 20 + 15], 1, 'prepared again, with the new wall')

	# A fresh service whose first compute (preparing open ground) is still running when
	# the ground changes: what it prepared is never taken up.
	var fresh := LFFlowFieldService.new(30.0, 3.0, 0.1)
	fresh.request_field(goal)
	fresh.tick(0.0)
	fresh.set_nav_grid({'cols': 20, 'rows': 20, 'blocked': blocked, 'heights': heights})
	await _wait_ready(fresh, goal)
	await _wait_idle(fresh)
	assert_eq(fresh._ground.blocked[5 * 20 + 15], 1, 'the new ground, not the one prepared before the change')
	assert_true(fresh.field_for(goal).directions
		== LFFlowField.compute(goal, 30.0, 3.0, [], fresh.density_weight, fresh.nav_grid).directions,
		'the field routes over the new ground')


func test_a_newly_wanted_field_is_due_on_the_next_tick_even_if_the_interval_grew_since():
	var service := LFFlowFieldService.new(30.0, 3.0, 1.0)
	var goal := Vector3(20, 0, 0)
	service.request_field(goal)
	service.refresh_interval = 60.0
	service.tick(0.0)
	assert_true(service.is_pending(goal), 'a field nobody has computed yet does not wait for the interval')
	await _wait_idle(service)


func test_a_nan_refresh_interval_is_rejected_and_the_value_is_kept():
	var service := LFFlowFieldService.new(9.0, 3.0, 3.0)
	service.refresh_interval = NAN
	assert_push_error('NaN')
	assert_eq(service.refresh_interval, 3.0)
	assert_eq(LFFlowFieldService.new(9.0, 3.0, NAN).refresh_interval, LFFlowFieldService.DEFAULT_REFRESH_INTERVAL)
	assert_push_error_count(2)
