extends GutTest

## One step length, in seconds.
const STEP_SECONDS := 0.1
## Attractor power, in units per second.
const POWER := 100.0
## Enough steps for the drag to settle the velocity.
const SETTLE_STEPS := 400
## Comparison tolerance.
const TOLERANCE := 0.01

var _pull: LFMagnetPull3D


func before_each() -> void:
	_pull = LFMagnetPull3D.new()


func _attractor(at: Vector3) -> Node3D:
	var node: Node3D = add_child_autofree(Node3D.new())
	node.global_position = at
	return node


func test_no_attractors_gives_zero_velocity() -> void:
	assert_eq(_pull.step(Vector3.ZERO, STEP_SECONDS), Vector3.ZERO)


func test_first_step_is_direction_times_power_times_delta() -> void:
	_pull.set_attractor(_attractor(Vector3(0, 0, 50)), POWER)
	var v := _pull.step(Vector3.ZERO, STEP_SECONDS)
	assert_almost_eq(v.z, POWER * STEP_SECONDS, TOLERANCE)
	assert_almost_eq(v.x, 0.0, TOLERANCE)


func test_velocity_settles_at_the_power_of_a_lone_attractor() -> void:
	_pull.set_attractor(_attractor(Vector3(1000000, 0, 0)), POWER)
	var v := Vector3.ZERO
	for i in SETTLE_STEPS:
		v = _pull.step(Vector3.ZERO, STEP_SECONDS)
	assert_almost_eq(v.x, POWER, TOLERANCE)


func test_powers_add_in_three_axes() -> void:
	_pull.set_attractor(_attractor(Vector3(10, 0, 0)), POWER)
	_pull.set_attractor(_attractor(Vector3(0, 10, 0)), POWER * 2.0)
	_pull.set_attractor(_attractor(Vector3(0, 0, 10)), POWER * 3.0)
	assert_eq(_pull.force_at(Vector3.ZERO).round(), Vector3(POWER, POWER * 2.0, POWER * 3.0))


func test_removed_and_freed_attractors_stop_pulling() -> void:
	var kept := _attractor(Vector3(10, 0, 0))
	var freed := _attractor(Vector3(0, 10, 0))
	_pull.set_attractor(kept, POWER)
	_pull.set_attractor(freed, POWER)
	freed.free()
	assert_eq(_pull.attractor_count(), 1)
	_pull.remove_attractor(kept)
	assert_eq(_pull.step(Vector3.ZERO, STEP_SECONDS), Vector3.ZERO)
	assert_false(_pull.has_attractor(kept))


func test_clear_drops_attractors_and_velocity() -> void:
	_pull.set_attractor(_attractor(Vector3(10, 0, 0)), POWER)
	_pull.step(Vector3.ZERO, STEP_SECONDS)
	_pull.clear()
	assert_eq(_pull.velocity, Vector3.ZERO)
	assert_eq(_pull.attractor_count(), 0)


func test_nan_power_is_rejected_and_changes_nothing() -> void:
	var node := _attractor(Vector3(10, 0, 0))
	_pull.set_attractor(node, POWER)
	_pull.set_attractor(node, NAN)
	assert_eq(_pull.force_at(Vector3.ZERO).round(), Vector3(POWER, 0, 0))
	var other := _attractor(Vector3(0, 10, 0))
	_pull.set_attractor(other, NAN)
	assert_false(_pull.has_attractor(other))
	assert_push_error_count(2)


func test_set_attractor_again_changes_power_and_off_removes() -> void:
	var node := _attractor(Vector3(10, 0, 0))
	_pull.set_attractor(node, POWER)
	_pull.set_attractor(node, POWER * 2.0)
	assert_eq(_pull.attractor_count(), 1)
	assert_eq(_pull.force_at(Vector3.ZERO).round(), Vector3(POWER * 2.0, 0, 0))
	_pull.set_attractor(node, POWER, false)
	assert_false(_pull.has_attractor(node))


func test_attractor_at_the_body_position_adds_nothing() -> void:
	_pull.set_attractor(_attractor(Vector3(1, 2, 3)), POWER)
	assert_eq(_pull.force_at(Vector3(1, 2, 3)), Vector3.ZERO)


func test_force_at_changes_nothing() -> void:
	_pull.set_attractor(_attractor(Vector3(10, 0, 0)), POWER)
	_pull.force_at(Vector3.ZERO)
	assert_eq(_pull.velocity, Vector3.ZERO)


func test_attractor_outside_the_tree_is_skipped() -> void:
	var node := Node3D.new()
	autofree(node)
	_pull.set_attractor(node, POWER)
	assert_eq(_pull.attractor_count(), 0)
	assert_eq(_pull.step(Vector3.ZERO, STEP_SECONDS), Vector3.ZERO)


func test_removing_an_absent_attractor_is_harmless() -> void:
	_pull.remove_attractor(_attractor(Vector3.ONE))
	assert_eq(_pull.attractor_count(), 0)


func test_equal_opposite_attractors_cancel() -> void:
	_pull.set_attractor(_attractor(Vector3(10, 0, 0)), POWER)
	_pull.set_attractor(_attractor(Vector3(-10, 0, 0)), POWER)
	assert_eq(_pull.step(Vector3.ZERO, STEP_SECONDS).round(), Vector3.ZERO)


func test_removing_a_freed_attractor_does_not_error_and_forgets_it() -> void:
	var node := _attractor(Vector3(10, 0, 0))
	var other := _attractor(Vector3(20, 0, 0))
	_pull.set_attractor(node, POWER)
	_pull.set_attractor(other, POWER)
	node.free()
	_pull.remove_attractor(node)
	assert_false(_pull.has_attractor(node))
	assert_eq(_pull.attractor_count(), 1)
	assert_true(_pull.has_attractor(other))


func test_has_attractor_is_false_for_a_freed_node() -> void:
	var node := _attractor(Vector3(10, 0, 0))
	_pull.set_attractor(node, POWER)
	node.free()
	assert_false(_pull.has_attractor(node))
