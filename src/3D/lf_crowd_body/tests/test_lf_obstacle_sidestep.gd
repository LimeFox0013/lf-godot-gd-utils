extends GutTest

const SPEED := 4.0
const GRAVITY := 30.0


func _floor() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position = Vector3(0, -1.0, 0)
	ground.add_child(shape)
	add_child_autofree(ground)


## A 1 x 3 x 2 block standing across the path from x = 1 to x = 2.
func _block(at := Vector3(1.5, 0.5, 0)) -> void:
	var block := StaticBody3D.new()
	block.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 3, 2)
	shape.shape = box
	block.add_child(shape)
	block.position = at
	add_child_autofree(block)


func _body(position: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 5
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	body.add_child(shape)
	body.position = position
	add_child_autofree(body)
	return body


## Walks `body` toward `goal` for `frames` physics steps, steering with `sidestep` when given.
func _walk(body: CharacterBody3D, goal: Vector3, frames: int, sidestep: LFObstacleSidestep = null) -> void:
	var delta := 1.0 / 60.0
	for i in frames:
		var to_goal := goal - body.global_position
		to_goal.y = 0.0
		var direction := to_goal.normalized()
		if sidestep != null:
			direction = sidestep.steer(body, direction, to_goal, delta)
		body.velocity.x = direction.x * SPEED
		body.velocity.z = direction.z * SPEED
		body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - GRAVITY * delta
		body.move_and_slide()


func test_without_a_sidestep_a_body_meeting_a_wall_square_on_presses_into_it():
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	_walk(body, Vector3(10, 0.5, 0), 600)
	assert_lt(body.global_position.x, 1.0, 'the fixture really stops a plain body')


func test_a_body_meeting_a_wall_square_on_walks_round_it():
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	_walk(body, Vector3(10, 0.5, 0), 600, LFObstacleSidestep.new())
	assert_gt(body.global_position.x, 2.0, 'it got past the obstacle')


func test_away_from_walls_the_direction_is_unchanged():
	_floor()
	var body := _body(Vector3(0, 0.5, 0))
	var sidestep := LFObstacleSidestep.new()
	_walk(body, Vector3(10, 0.5, 0), 5)
	assert_eq(sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.016), Vector3(1, 0, 0))
	assert_false(sidestep.is_sidestepping())


func test_a_sidestep_is_a_unit_step_along_the_wall_held_for_its_seconds():
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	var sidestep := LFObstacleSidestep.new(0.9, 0.5, 0.4)
	_walk(body, Vector3(10, 0.5, 0), 60)
	assert_true(body.is_on_wall(), 'pressing into the block')
	var side := sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 1.0 / 60.0)
	assert_almost_eq(side.length(), 1.0, 0.001)
	assert_almost_eq(side.x, 0.0, 0.001, 'along the face, not into it')
	assert_true(sidestep.is_sidestepping())
	assert_eq(sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.2), side, 'held')
	sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.3)
	assert_false(sidestep.is_sidestepping(), 'released after its seconds')


func test_reset_ends_a_sidestep():
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	var sidestep := LFObstacleSidestep.new()
	_walk(body, Vector3(10, 0.5, 0), 60)
	sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 1.0 / 60.0)
	sidestep.reset()
	assert_false(sidestep.is_sidestepping())


func test_reset_forgets_the_remembered_side():
	var body := _pressed_body()
	var sidestep := LFObstacleSidestep.new()
	var first := sidestep.steer(body, Vector3(1, 0, -0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0)
	sidestep.reset()
	var again := sidestep.steer(body, Vector3(1, 0, 0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0)
	assert_lt(first.z, 0.0)
	assert_gt(again.z, 0.0, 'the new lean decides, not the forgotten side')


func test_a_glancing_hit_slides_instead_of_sidestepping():
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	var sidestep := LFObstacleSidestep.new()
	_walk(body, Vector3(10, 0.5, 0), 60)
	var glancing := Vector3(1, 0, 1).normalized()
	assert_eq(sidestep.steer(body, glancing, Vector3(10, 0, 0), 1.0 / 60.0), glancing, 'not head-on enough')


## A body pressed into the block's -X face, square on.
func _pressed_body() -> CharacterBody3D:
	_floor()
	_block()
	var body := _body(Vector3(0, 0.5, 0))
	_walk(body, Vector3(10, 0.5, 0), 60)
	return body


func test_a_leaning_hit_steps_the_way_the_slide_leans():
	var body := _pressed_body()
	var leaning_left := Vector3(1, 0, -0.2).normalized()
	assert_lt(LFObstacleSidestep.new().steer(body, leaning_left, Vector3(10, 0, 0), 1.0 / 60.0).z, 0.0)
	var leaning_right := Vector3(1, 0, 0.2).normalized()
	assert_gt(LFObstacleSidestep.new().steer(body, leaning_right, Vector3(10, 0, 0), 1.0 / 60.0).z, 0.0)


func test_a_dead_centre_hit_steps_toward_the_destination():
	var body := _pressed_body()
	var sidestep := LFObstacleSidestep.new()
	sidestep.dead_center_slide = 0.5
	var leaning_left := Vector3(1, 0, -0.2).normalized()
	var side := sidestep.steer(body, leaning_left, Vector3(10, 0, 3), 1.0 / 60.0)
	assert_gt(side.z, 0.0, "a lean under dead_center_slide counts as dead centre")


func test_the_same_face_met_again_soon_keeps_the_same_side():
	var body := _pressed_body()
	var sidestep := LFObstacleSidestep.new(0.9, 0.5, 0.4, 2.0)
	var first := sidestep.steer(body, Vector3(1, 0, -0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0)
	sidestep.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.5)
	assert_false(sidestep.is_sidestepping())
	var again := sidestep.steer(body, Vector3(1, 0, 0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0)
	assert_eq(again, first, "remembered, though the slide now leans the other way")

	var forgetful := LFObstacleSidestep.new(0.9, 0.5, 0.4, 0.1)
	forgetful.steer(body, Vector3(1, 0, -0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0)
	forgetful.steer(body, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.5)
	assert_gt(forgetful.steer(body, Vector3(1, 0, 0.2).normalized(), Vector3(10, 0, 0), 1.0 / 60.0).z, 0.0, "past memory_seconds the lean decides")


func test_a_blocked_side_turns_the_step_the_other_way():
	var body := _pressed_body()
	_block(Vector3(0, 0.5, -1.2))
	var leaning_left := Vector3(1, 0, -0.2).normalized()
	assert_gt(LFObstacleSidestep.new().steer(body, leaning_left, Vector3(10, 0, 0), 1.0 / 60.0).z, 0.0)


func test_a_lower_head_on_dot_sidesteps_a_glancing_hit_too():
	var body := _pressed_body()
	var sidestep := LFObstacleSidestep.new()
	sidestep.head_on_dot = 0.5
	var glancing := Vector3(1, 0, 1).normalized()
	var side := sidestep.steer(body, glancing, Vector3(10, 0, 0), 1.0 / 60.0)
	assert_ne(side, glancing, "45 degrees is square enough at 0.5")
	assert_almost_eq(side.x, 0.0, 0.001, "a step along the face, not into it")
	assert_true(sidestep.is_sidestepping())


func test_a_new_sidestep_starts_with_the_documented_defaults():
	var sidestep := LFObstacleSidestep.new()
	assert_eq(sidestep.head_on_dot, 0.9)
	assert_eq(sidestep.dead_center_slide, 0.05)
	assert_eq(sidestep.probe_distance, 0.5)
	assert_eq(sidestep.hold_seconds, 0.4)
	assert_eq(sidestep.memory_seconds, 2.0)
	assert_false(sidestep.is_sidestepping())


func test_a_dead_centre_hit_with_the_destination_on_the_other_side_steps_that_way():
	var body := _pressed_body()
	var side := LFObstacleSidestep.new().steer(body, Vector3(1, 0, 0), Vector3(10, 0, -3), 1.0 / 60.0)
	assert_almost_eq(side, Vector3(0, 0, -1), Vector3.ONE * 0.001)
