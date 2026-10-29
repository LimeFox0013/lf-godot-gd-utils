extends GutTest


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_start_adds_a_child_to_the_node_and_remembers_its_position_as_the_base():
	var node: Control = add_child_autofree(Control.new())
	node.position = Vector2(40, 50)

	var drift := LFIdleDrift.start(node)

	assert_not_null(drift)
	assert_eq(drift.get_parent(), node)
	assert_eq(drift.base_position, Vector2(40, 50))
	assert_eq(drift.amplitude, LFIdleDrift.DEFAULT_AMPLITUDE)
	assert_eq(drift.speed, LFIdleDrift.DEFAULT_SPEED)


func test_start_refuses_a_null_a_freed_or_3d_node():
	var freed := Control.new()
	freed.free()
	var node_3d: Node3D = add_child_autofree(Node3D.new())

	assert_null(LFIdleDrift.start(null))
	assert_null(LFIdleDrift.start(freed))
	assert_null(LFIdleDrift.start(node_3d))


func test_the_node_stays_within_the_amplitude_of_the_base_position():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.position = Vector2(100, 100)
	var drift := LFIdleDrift.start(node, Vector2(10, 4), 0.5, _rng(1))

	var farthest := Vector2.ZERO
	for i in 200:
		drift.step(0.05)
		farthest = farthest.max((node.position - Vector2(100, 100)).abs())

	assert_lte(farthest.x, 10.0 + 0.001)
	assert_lte(farthest.y, 4.0 + 0.001)
	assert_gt(farthest.x, 5.0, "it really drifts")
	assert_gt(farthest.y, 2.0)


func test_x_follows_a_sine_at_the_speed_and_y_at_the_ratio_with_the_phase():
	var node: Node2D = add_child_autofree(Node2D.new())
	var drift := LFIdleDrift.start(node, Vector2(10, 20), 0.25, _rng(2))
	drift.phase = 0.4

	drift.step(1.0)

	var angle := TAU * 0.25
	assert_almost_eq(node.position.x, sin(angle) * 10.0, 0.0001)
	assert_almost_eq(node.position.y, sin(angle * LFIdleDrift.Y_SPEED_RATIO + 0.4) * 20.0, 0.0001)
	assert_eq(LFIdleDrift.Y_SPEED_RATIO, 0.73)


func test_the_same_seed_gives_the_same_phase_and_another_seed_another():
	var node: Node2D = add_child_autofree(Node2D.new())
	var first := LFIdleDrift.start(node, Vector2.ONE, 1.0, _rng(7))
	var second := LFIdleDrift.start(node, Vector2.ONE, 1.0, _rng(7))
	var other := LFIdleDrift.start(node, Vector2.ONE, 1.0, _rng(8))

	assert_eq(first.phase, second.phase)
	assert_ne(first.phase, other.phase)
	assert_between(first.phase, 0.0, TAU)


func test_paused_holds_the_node_and_the_clock_and_resuming_carries_on():
	var node: Node2D = add_child_autofree(Node2D.new())
	var drift := LFIdleDrift.start(node, Vector2(10, 10), 0.5, _rng(3))
	drift.step(0.3)
	var held := node.position
	var clock := drift.elapsed

	drift.paused = true
	drift.step(5.0)

	assert_eq(node.position, held)
	assert_eq(drift.elapsed, clock)
	drift.paused = false
	drift.step(0.3)
	assert_almost_eq(drift.elapsed, clock + 0.3, 0.0001)
	assert_ne(node.position, held)


func test_it_drifts_by_itself_every_frame():
	var node: Node2D = add_child_autofree(Node2D.new())
	LFIdleDrift.start(node, Vector2(50, 50), 2.0, _rng(4))

	await wait_seconds(0.2)

	assert_ne(node.position, Vector2.ZERO)


func test_base_position_can_be_moved():
	var node: Node2D = add_child_autofree(Node2D.new())
	var drift := LFIdleDrift.start(node, Vector2(1, 1), 1.0, _rng(5))
	drift.base_position = Vector2(500, 500)

	drift.step(0.1)

	assert_lt(node.position.distance_to(Vector2(500, 500)), 2.0)


func test_stop_restores_the_base_position_and_frees_the_drift_or_leaves_the_node_where_it_is():
	var node: Node2D = add_child_autofree(Node2D.new())
	node.position = Vector2(9, 9)
	var drift := LFIdleDrift.start(node, Vector2(10, 10), 1.0, _rng(6))
	drift.step(0.3)

	drift.stop()
	await wait_process_frames(2)

	assert_eq(node.position, Vector2(9, 9))
	assert_false(is_instance_valid(drift))

	var again := LFIdleDrift.start(node, Vector2(10, 10), 1.0, _rng(6))
	again.step(0.3)
	var where := node.position
	again.stop(false)
	assert_eq(node.position, where)


func test_the_drift_is_freed_with_its_node():
	var node := Node2D.new()
	add_child(node)
	var drift := LFIdleDrift.start(node)
	var ref: WeakRef = weakref(drift)

	node.free()
	await wait_process_frames(1)

	assert_null(ref.get_ref())
