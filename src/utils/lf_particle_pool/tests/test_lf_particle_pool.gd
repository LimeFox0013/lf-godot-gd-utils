extends GutTest

## How many copies the tests warm up.
const WARM_UP := 2

var _holder: Node3D
var _reference: GPUParticles3D


func before_each():
	_holder = add_child_autofree(Node3D.new())
	_reference = GPUParticles3D.new()
	_reference.one_shot = true
	_reference.emitting = false
	_reference.process_material = ParticleProcessMaterial.new()
	_reference.draw_pass_1 = BoxMesh.new()
	_holder.add_child(_reference)


func _make_pool(warm := WARM_UP) -> LFParticlePool:
	var pool := LFParticlePool.new()
	pool.reference = _reference
	pool.warm_up = warm
	_holder.add_child(pool)
	return pool


func test_it_warms_up_copies_into_the_references_parent():
	var pool := _make_pool()
	assert_eq(pool.pooled_count(), WARM_UP)
	assert_eq(_holder.get_child_count(), 2 + WARM_UP, "the reference, the pool and the copies")


func test_a_copy_has_its_own_materials():
	var pool := _make_pool()
	var first: GPUParticles3D = pool.acquire()
	var second: GPUParticles3D = pool.acquire()
	assert_ne(first.process_material, _reference.process_material)
	assert_ne(first.process_material, second.process_material)
	assert_ne(first.draw_pass_1, second.draw_pass_1)
	first.process_material.color = Color.RED
	assert_ne(second.process_material.color, Color.RED)
	assert_ne(_reference.process_material.color, Color.RED)


func test_a_copy_keeps_the_references_settings():
	_reference.amount = 7
	_reference.lifetime = 3.0
	var pool := _make_pool()
	var copy: GPUParticles3D = pool.acquire()
	assert_eq(copy.amount, 7)
	assert_eq(copy.lifetime, 3.0)
	assert_true(copy.one_shot)


func test_a_finished_copy_returns_to_the_pool_and_is_reused():
	var pool := _make_pool(0)
	var copy: GPUParticles3D = pool.acquire()
	assert_eq(pool.pooled_count(), 0)
	copy.finished.emit()
	assert_eq(pool.pooled_count(), 1)
	assert_same(pool.acquire(), copy, "the same node comes back")
	copy.finished.emit()
	assert_eq(pool.pooled_count(), 1)
	assert_same(pool.acquire(), copy, "still one connection: no double release")


func test_a_released_copy_stops_emitting():
	var pool := _make_pool(0)
	var copy: GPUParticles3D = pool.acquire()
	copy.emitting = true
	assert_true(pool.release(copy))
	assert_false(copy.emitting)
	assert_false(pool.release(copy), "already back")
	assert_false(pool.release(autofree(Node.new())))


func test_it_works_with_2d_particles_too():
	var holder: Node2D = add_child_autofree(Node2D.new())
	var reference := GPUParticles2D.new()
	reference.process_material = ParticleProcessMaterial.new()
	holder.add_child(reference)
	var pool := LFParticlePool.new()
	pool.reference = reference
	pool.warm_up = 1
	holder.add_child(pool)
	var copy: GPUParticles2D = pool.acquire()
	assert_ne(copy.process_material, reference.process_material)
	copy.finished.emit()
	assert_eq(pool.pooled_count(), 1)


func test_an_explicit_container_receives_the_copies():
	var elsewhere: Node3D = add_child_autofree(Node3D.new())
	var pool := LFParticlePool.new()
	pool.reference = _reference
	pool.container = elsewhere
	pool.warm_up = 1
	_holder.add_child(pool)
	assert_eq(elsewhere.get_child_count(), 1)


func test_a_missing_or_wrong_reference_is_reported_and_acquire_gives_null():
	var pool := LFParticlePool.new()
	_holder.add_child(pool)
	assert_push_error('LFParticlePool')
	assert_null(pool.acquire())
	assert_push_error('LFParticlePool')
	var wrong := LFParticlePool.new()
	wrong.reference = Node3D.new()
	autofree(wrong.reference)
	_holder.add_child(wrong)
	assert_push_error('LFParticlePool')


func test_a_zero_or_negative_warm_up_builds_nothing_but_acquire_still_works():
	var pool := _make_pool(-3)
	assert_eq(pool.pooled_count(), 0)
	assert_not_null(pool.acquire())


func test_the_default_warm_up_is_used_when_none_is_set():
	var pool := LFParticlePool.new()
	pool.reference = _reference
	assert_eq(pool.warm_up, LFParticlePool.DEFAULT_WARM_UP)
	_holder.add_child(pool)
	assert_eq(pool.pooled_count(), LFParticlePool.DEFAULT_WARM_UP)
