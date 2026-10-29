extends GutTest

var ring: LFFollowRing3D


func before_each():
	ring = LFFollowRing3D.new()
	add_child_autofree(ring)


func _target(at: Vector3) -> Node3D:
	var node: Node3D = add_child_autofree(Node3D.new())
	node.position = at
	return node


func test_hidden_without_a_target():
	assert_false(ring.visible)


func test_sits_lifted_above_its_target_and_follows_it():
	var node := _target(Vector3(3, 0, -2))

	ring.target = node
	assert_true(ring.visible)
	assert_eq(ring.global_position, Vector3(3, LFFollowRing3D.DEFAULT_LIFT, -2))

	node.position = Vector3(-1, 0, 5)
	await wait_process_frames(1)
	assert_almost_eq(ring.global_position.x, -1.0, 0.001)
	assert_almost_eq(ring.global_position.z, 5.0, 0.001)


func test_hides_when_the_target_is_cleared_or_freed():
	ring.target = _target(Vector3.ZERO)
	ring.target = null
	assert_false(ring.visible)

	var doomed := Node3D.new()
	add_child(doomed)
	ring.target = doomed
	doomed.free()
	await wait_process_frames(1)
	assert_false(ring.visible)


func test_processes_only_while_it_has_a_target():
	assert_false(ring.is_processing())
	ring.target = _target(Vector3.ZERO)
	assert_true(ring.is_processing())

	ring.target = null
	assert_false(ring.is_processing())


func test_pulse_swings_the_scale_within_the_amount():
	ring.target = _target(Vector3.ZERO)
	for i in 30:
		ring._process(0.1)
		assert_between(ring.scale.x, 1.0 - LFFollowRing3D.DEFAULT_PULSE_AMOUNT - 0.0001, 1.0 + LFFollowRing3D.DEFAULT_PULSE_AMOUNT + 0.0001)


func test_constructor_values_shape_the_ring_and_the_pulse():
	var custom := LFFollowRing3D.new(2.0, 2.5, Color.RED, 1.0, 0.5, 0.2)
	add_child_autofree(custom)
	var torus := (custom.get_child(0) as MeshInstance3D).mesh as TorusMesh
	var material := (custom.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D

	assert_eq([torus.inner_radius, torus.outer_radius], [2.0, 2.5])
	assert_eq(material.albedo_color, Color.RED)
	custom.target = _target(Vector3(1, 0, 1))
	assert_eq(custom.global_position, Vector3(1, 0.2, 1))
	custom._process(PI / 2.0)
	assert_almost_eq(custom.scale.x, 1.5, 0.001)


func test_target_set_before_entering_the_tree_is_followed_once_ready():
	var node := _target(Vector3(2, 0, 2))
	var early := LFFollowRing3D.new()
	early.target = node
	add_child_autofree(early)

	assert_true(early.visible)
	assert_true(early.is_processing())
	assert_eq(early.global_position, Vector3(2, LFFollowRing3D.DEFAULT_LIFT, 2))


func test_hides_when_the_target_leaves_the_tree():
	var node := _target(Vector3.ZERO)
	ring.target = node
	remove_child(node)
	await wait_process_frames(1)

	assert_false(ring.visible)
	assert_false(ring.is_processing())
	node.free()


func test_lift_can_change_after_construction():
	var node := _target(Vector3(0, 1, 0))
	ring.lift = 0.5
	ring.target = node

	assert_eq(ring.global_position, Vector3(0, 1.5, 0))
