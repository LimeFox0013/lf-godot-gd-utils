extends GutTest

const SPEED := 12.0


class Picky:
	extends LFProjectile3D
	var landed_on: Array[Area3D] = []

	func _accepts_area(area: Area3D) -> bool:
		return area.name == "Wanted"

	func _landed_on(area: Area3D) -> void:
		landed_on.append(area)
		super(area)


func _projectile(script_class: GDScript = null, in_tree := true) -> LFProjectile3D:
	var projectile: LFProjectile3D = script_class.new() if script_class != null else LFProjectile3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	projectile.add_child(shape)
	if in_tree:
		add_child_autofree(projectile)
	return projectile


func _area_at(position: Vector3, area_name := "Area") -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	area.add_child(shape)
	area.position = position
	add_child_autofree(area)
	return area


func _pool() -> LFFactory:
	var pool := LFFactory.new()
	var container := Node3D.new()
	add_child_autofree(container)
	pool.set_container(container)
	pool.register(&"shot", func() -> Node: return _projectile(null, false), Callable(), func(shot: LFProjectile3D) -> void: shot.reset())
	return pool


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func test_it_flies_to_the_aim_point_and_frees_itself_without_a_pool():
	var projectile := _projectile()
	projectile.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	assert_true(projectile.is_flying())
	await _physics(10)
	assert_true(projectile.is_flying(), "6 units at 12 per second is not done in 10 frames")
	assert_gt(projectile.global_position.x, 0.0)
	assert_lt(projectile.global_position.x, 6.0)
	await _physics(60)
	assert_false(is_instance_valid(projectile))


func test_it_flies_an_inclined_straight_line():
	var projectile := _projectile()
	projectile.launch_to(Vector3(0, 3, 0), Vector3(4, 0, 0), SPEED)
	await _physics(5)
	var travelled := projectile.global_position - Vector3(0, 3, 0)
	assert_almost_eq(travelled.normalized(), Vector3(4, -3, 0).normalized(), Vector3(0.001, 0.001, 0.001))


func test_a_shot_with_no_distance_to_cover_finishes_without_moving():
	var projectile := _projectile()
	projectile.launch_to(Vector3(1, 1, 1), Vector3(1, 1, 1), SPEED)
	await _physics(2)
	assert_false(is_instance_valid(projectile))


func test_it_finishes_on_the_first_area_it_enters():
	var picky := _projectile(Picky) as Picky
	var landed := picky.landed_on
	_area_at(Vector3(3, 0, 0), "Wanted")
	picky.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(40)
	assert_eq(landed.size(), 1)
	assert_false(is_instance_valid(picky))


func test_areas_it_does_not_accept_are_flown_through():
	var picky := _projectile(Picky) as Picky
	var landed := picky.landed_on
	_area_at(Vector3(2, 0, 0), "Unwanted")
	_area_at(Vector3(4, 0, 0), "Wanted")
	picky.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(40)
	assert_eq(landed.size(), 1)
	assert_eq(landed[0].name, "Wanted")


func test_overlapping_areas_in_one_step_land_only_once():
	var picky := _projectile(Picky) as Picky
	var landed := picky.landed_on
	_area_at(Vector3(3, 0, 0), "Wanted")
	_area_at(Vector3(3, 0, 0), "Wanted")
	picky.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(40)
	assert_eq(landed.size(), 1)


func test_without_an_override_any_area_ends_the_flight():
	var projectile := _projectile()
	_area_at(Vector3(3, 0, 0))
	projectile.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(20)
	assert_false(is_instance_valid(projectile))


func test_a_pooled_projectile_returns_to_its_pool_after_a_hit_and_after_a_miss():
	var pool := _pool()
	var hit: LFProjectile3D = pool.acquire(&"shot")
	hit.pool = pool
	var target := _area_at(Vector3(3, 0, 0))
	hit.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(30)
	assert_true(pool.is_pooled(hit), "a hit goes back to the pool")
	target.free()
	var miss: LFProjectile3D = pool.acquire(&"shot")
	assert_eq(miss, hit, "the pooled one is handed out again")
	miss.pool = pool
	miss.launch_to(Vector3(0, 0, 9), Vector3(0, 0, 12), SPEED)
	await _physics(40)
	assert_true(pool.is_pooled(miss), "a miss goes back to the pool")


func test_reset_leaves_it_idle_and_detecting_nothing():
	var projectile := _projectile()
	projectile.launch_to(Vector3.ZERO, Vector3(6, 0, 0), SPEED)
	await _physics(2)
	assert_true(projectile.monitoring)
	assert_true(projectile.monitorable)
	projectile.reset()
	assert_false(projectile.is_flying())
	assert_false(projectile.visible)
	assert_false(projectile.is_physics_processing())
	assert_eq(projectile._traveled, 0.0)
	assert_eq(projectile._speed, 0.0)
	await _physics(1)
	assert_false(projectile.monitoring)
	assert_false(projectile.monitorable)


func test_reset_then_launch_in_one_frame_ends_enabled():
	var projectile := _projectile()
	projectile.launch_to(Vector3.ZERO, Vector3(60, 0, 0), SPEED)
	await _physics(1)
	projectile.reset()
	projectile.launch_to(Vector3.ZERO, Vector3(60, 0, 0), SPEED)
	await _physics(2)
	assert_true(projectile.monitoring)
	assert_true(projectile.monitorable)
	assert_true(projectile.visible)


func test_a_launched_projectile_is_visible_and_physics_processing():
	var projectile := _projectile()
	projectile.visible = false
	projectile.launch_to(Vector3.ZERO, Vector3(60, 0, 0), SPEED)
	assert_true(projectile.visible)
	assert_true(projectile.is_physics_processing())
