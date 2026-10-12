extends GutTest

## One step length, in seconds.
const STEP_SECONDS := 0.1
## Attractor power, in units per second.
const POWER := 100.0
## Enough steps for the drag to settle the velocity.
const SETTLE_STEPS := 400
## Comparison tolerance.
const TOLERANCE := 0.01

var _pull: LFMagnetPull2D


func before_each() -> void:
	_pull = LFMagnetPull2D.new()


func _attractor(at: Vector2) -> Node2D:
	var node: Node2D = add_child_autofree(Node2D.new())
	node.global_position = at
	return node


func test_no_attractors_gives_zero_velocity() -> void:
	assert_eq(_pull.step(Vector2.ZERO, STEP_SECONDS), Vector2.ZERO)
	assert_eq(_pull.force_at(Vector2.ZERO), Vector2.ZERO)


func test_first_step_is_direction_times_power_times_delta() -> void:
	_pull.set_attractor(_attractor(Vector2(50, 0)), POWER)
	var v := _pull.step(Vector2.ZERO, STEP_SECONDS)
	assert_almost_eq(v.x, POWER * STEP_SECONDS, TOLERANCE)
	assert_almost_eq(v.y, 0.0, TOLERANCE)


func test_velocity_settles_at_the_power_of_a_lone_attractor() -> void:
	_pull.set_attractor(_attractor(Vector2(0, 1000000)), POWER)
	var v := Vector2.ZERO
	for i in SETTLE_STEPS:
		v = _pull.step(Vector2.ZERO, STEP_SECONDS)
	assert_almost_eq(v.y, POWER, TOLERANCE)


func test_powers_of_several_attractors_add() -> void:
	_pull.set_attractor(_attractor(Vector2(10, 0)), POWER)
	_pull.set_attractor(_attractor(Vector2(0, 10)), POWER * 2.0)
	var force := _pull.force_at(Vector2.ZERO)
	assert_almost_eq(force.x, POWER, TOLERANCE)
	assert_almost_eq(force.y, POWER * 2.0, TOLERANCE)


func test_opposite_attractors_cancel() -> void:
	_pull.set_attractor(_attractor(Vector2(10, 0)), POWER)
	_pull.set_attractor(_attractor(Vector2(-10, 0)), POWER)
	assert_almost_eq(_pull.force_at(Vector2.ZERO).length(), 0.0, TOLERANCE)


func test_force_subtracts_the_current_velocity() -> void:
	_pull.set_attractor(_attractor(Vector2(10, 0)), POWER)
	_pull.step(Vector2.ZERO, 1.0)
	assert_almost_eq(_pull.force_at(Vector2.ZERO).x, 0.0, TOLERANCE)


func test_attractor_at_the_same_position_adds_nothing() -> void:
	_pull.set_attractor(_attractor(Vector2(5, 5)), POWER)
	assert_eq(_pull.force_at(Vector2(5, 5)), Vector2.ZERO)


func test_removing_the_last_attractor_zeroes_velocity() -> void:
	var node := _attractor(Vector2(10, 0))
	_pull.set_attractor(node, POWER)
	_pull.step(Vector2.ZERO, STEP_SECONDS)
	_pull.set_attractor(node, POWER, false)
	assert_false(_pull.has_attractor(node))
	assert_eq(_pull.step(Vector2.ZERO, STEP_SECONDS), Vector2.ZERO)


func test_set_attractor_again_changes_the_power() -> void:
	var node := _attractor(Vector2(10, 0))
	_pull.set_attractor(node, POWER)
	_pull.set_attractor(node, POWER * 2.0)
	assert_eq(_pull.attractor_count(), 1)
	assert_almost_eq(_pull.force_at(Vector2.ZERO).x, POWER * 2.0, TOLERANCE)


func test_freed_attractor_is_skipped() -> void:
	var node := _attractor(Vector2(10, 0))
	_pull.set_attractor(node, POWER)
	node.free()
	assert_eq(_pull.attractor_count(), 0)
	assert_eq(_pull.step(Vector2.ZERO, STEP_SECONDS), Vector2.ZERO)


func test_attractor_outside_the_tree_is_skipped() -> void:
	var node := Node2D.new()
	autofree(node)
	_pull.set_attractor(node, POWER)
	assert_eq(_pull.attractor_count(), 0)


func test_nan_power_is_rejected() -> void:
	var node := _attractor(Vector2(10, 0))
	_pull.set_attractor(node, NAN)
	assert_false(_pull.has_attractor(node))
	assert_push_error_count(1)


func test_clear_drops_attractors_and_velocity() -> void:
	_pull.set_attractor(_attractor(Vector2(10, 0)), POWER)
	_pull.step(Vector2.ZERO, STEP_SECONDS)
	_pull.clear()
	assert_eq(_pull.attractor_count(), 0)
	assert_eq(_pull.velocity, Vector2.ZERO)


func test_force_at_does_not_change_velocity() -> void:
	_pull.set_attractor(_attractor(Vector2(10, 0)), POWER)
	_pull.force_at(Vector2.ZERO)
	assert_eq(_pull.velocity, Vector2.ZERO)
