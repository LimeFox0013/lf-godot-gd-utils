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
