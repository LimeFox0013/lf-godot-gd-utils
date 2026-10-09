extends GutTest

const FLAT := Color(0.2, 0.5, 0.2)
const STEEP := Color(0.5, 0.4, 0.3)


func _vertex_color(mesh: ArrayMesh, at: Vector3) -> Variant:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in vertices.size():
		if vertices[i].is_equal_approx(at):
			return colors[i]
	return null


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func test_samples_for_covers_both_ends():
	assert_eq(LFHeightmap.samples_for(5.0, 1.0), 11)
	assert_eq(LFHeightmap.samples_for(5.0, 2.5), 5)


func test_a_flat_lattice_holds_one_zero_height_per_sample():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 0.0, 2.0, 1.0)
	assert_eq(data.size(), 25)
	for height in data:
		assert_eq(height, 0.0)


func test_the_lattice_samples_the_height_function_row_major():
	var data := LFHeightmap.lattice(func(x: float, z: float) -> float: return x + 10.0 * z, 1.0, 1.0)
	# samples 3: x in (-1, 0, 1), z in (-1, 0, 1); index iz * 3 + ix
	assert_eq(data[0], -11.0)
	assert_eq(data[1 * 3 + 2], 1.0)
	assert_eq(data[2 * 3 + 0], 9.0)


func test_bounds_evaluate_only_the_samples_they_cover():
	var calls := [0]
	var height := func(_x: float, _z: float) -> float:
		calls[0] += 1
		return 3.0
	var bounds: Array[Rect2] = [Rect2(0.5, 0.5, 1.0, 1.0)]
	var data := LFHeightmap.lattice(height, 2.0, 1.0, bounds)
	# Samples 5 at -2..2; the rect 0.5..1.5 widens to the samples at 0, 1 and 2 (ix, iz 2..4).
	assert_eq(calls[0], 9, "a 3 x 3 block")
	assert_eq(data[3 * 5 + 3], 3.0, "inside")
	assert_eq(data[0], 0.0, "outside stays flat")
	assert_eq(data[1 * 5 + 1], 0.0)


func test_slope_is_rise_over_run():
	# A ramp rising 1 per unit along X.
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return x, 2.0, 1.0)
	assert_almost_eq(LFHeightmap.slope_at(data, 5, 1.0, 2, 2), 1.0, 0.0001)
	assert_almost_eq(LFHeightmap.slope_at(data, 5, 1.0, 0, 2), 1.0, 0.0001, "one-sided at the edge, same slope")
	assert_almost_eq(LFHeightmap.slope_at(data, 5, 1.0, 4, 4), 1.0, 0.0001, "and at the far corner")
	var flat := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 4.0, 2.0, 1.0)
	assert_eq(LFHeightmap.slope_at(flat, 5, 1.0, 2, 2), 0.0)


func test_the_mesh_shades_flat_ground_flat_and_cliffs_steep():
	# A 3-unit step at x = 0.
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return 3.0 if x > 0.0 else 0.0, 3.0, 1.0)
	var mesh := LFHeightmap.build_mesh(data, 7, 1.0, 3.0, FLAT, STEEP)
	# Vertex colours are stored at 8 bits per channel.
	assert_true(_close(_vertex_color(mesh, Vector3(-3, 0, 0)), FLAT), "far from the cliff")
	assert_true(_close(_vertex_color(mesh, Vector3(0, 0, 0)), STEEP), "on the cliff edge")
	var gentle: Color = _vertex_color(LFHeightmap.build_mesh(data, 7, 1.0, 3.0, FLAT, STEEP, 3.0), Vector3(0, 0, 0))
	assert_almost_eq(gentle.r, FLAT.lerp(STEEP, 0.5).r, 0.001, "slope 1.5 of 3 is half way")


func test_the_mesh_vertices_span_the_lattice_extent():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 1.0, 4.0, 2.0)
	var mesh := LFHeightmap.build_mesh(data, 5, 2.0, 4.0, FLAT, STEEP)
	var aabb := mesh.get_aabb()
	assert_almost_eq(aabb.position, Vector3(-4, 1, -4), Vector3.ONE * 0.001)
	assert_almost_eq(aabb.size, Vector3(8, 0, 8), Vector3.ONE * 0.001)


func test_the_body_holds_a_matching_collider_and_mesh():
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return x, 2.0, 1.0)
	var body: StaticBody3D = autofree(LFHeightmap.build_body(data, 5, 1.0, 2.0, FLAT, STEEP, 4))
	assert_eq(body.collision_layer, 4)
	assert_eq(body.collision_mask, 0)
	var collision: CollisionShape3D = body.get_node("Collision")
	var shape := collision.shape as HeightMapShape3D
	assert_eq(shape.map_width, 5)
	assert_eq(shape.map_depth, 5)
	assert_eq(shape.map_data, data)
	assert_eq(collision.scale, Vector3.ONE)
	var mesh: MeshInstance3D = body.get_node("Mesh")
	assert_almost_eq(mesh.mesh.get_aabb().position, Vector3(-2, -2, -2), Vector3.ONE * 0.001, "the mesh covers the same lattice")
	assert_almost_eq(mesh.mesh.get_aabb().size, Vector3(4, 4, 4), Vector3.ONE * 0.001)
	assert_true((mesh.material_override as StandardMaterial3D).vertex_color_use_as_albedo)


func test_the_collider_is_scaled_to_a_wider_spacing():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 0.0, 4.0, 2.0)
	var body: StaticBody3D = autofree(LFHeightmap.build_body(data, 5, 2.0, 4.0, FLAT, STEEP))
	assert_eq((body.get_node("Collision") as CollisionShape3D).scale, Vector3(2, 1, 2))


func test_a_body_stops_a_ray_at_the_lattice_height():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 2.0, 4.0, 1.0)
	var body: StaticBody3D = add_child_autofree(LFHeightmap.build_body(data, 9, 1.0, 4.0, FLAT, STEEP))
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(1, 10, 1), Vector3(1, -10, 1))
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	assert_eq(hit.get("collider"), body)
	assert_almost_eq((hit["position"] as Vector3).y, 2.0, 0.01)


func test_bounds_outside_the_lattice_evaluate_nothing():
	var calls := [0]
	var height := func(_x: float, _z: float) -> float:
		calls[0] += 1
		return 3.0
	var bounds: Array[Rect2] = [Rect2(-10, -1, 4, 2), Rect2(5, 5, 2, 2)]
	var data := LFHeightmap.lattice(height, 2.0, 1.0, bounds)
	assert_eq(calls[0], 0, "no sample lies inside either rect")
	assert_eq(data.count(0.0), 25)


func test_slope_divides_by_the_spacing():
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return x, 4.0, 2.0)
	assert_almost_eq(LFHeightmap.slope_at(data, 5, 2.0, 2, 2), 1.0, 0.0001)
	assert_almost_eq(LFHeightmap.slope_at(data, 5, 2.0, 0, 0), 1.0, 0.0001)


func test_the_collider_lines_up_with_a_lattice_that_overshoots_its_half_extent():
	# half 2.5, spacing 2: 4 samples at -2.5, -0.5, 1.5, 3.5 — not centred on the origin.
	var samples := LFHeightmap.samples_for(2.5, 2.0)
	assert_eq(samples, 4)
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return x + 10.0, 2.5, 2.0)
	var body: StaticBody3D = add_child_autofree(LFHeightmap.build_body(data, samples, 2.0, 2.5, FLAT, STEEP))
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(-0.5, 50, -0.5), Vector3(-0.5, -50, -0.5))
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	assert_almost_eq((hit["position"] as Vector3).y, 9.5, 0.01, "the height sampled at x = -0.5")
	assert_almost_eq(_vertex_position_y(body, Vector3(-0.5, 0, -0.5)), 9.5, 0.001, "where the mesh has it")


func _vertex_position_y(body: StaticBody3D, at: Vector3) -> float:
	var vertices: PackedVector3Array = ((body.get_node("Mesh") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if is_equal_approx(vertex.x, at.x) and is_equal_approx(vertex.z, at.z):
			return vertex.y
	return NAN


func _surface_colors(steep_slope: Variant) -> PackedColorArray:
	# A ramp rising 1 unit per unit: between the steep thresholds tried below.
	var data := LFHeightmap.lattice(func(x: float, _z: float) -> float: return x, 2.0, 1.0)
	var samples := LFHeightmap.samples_for(2.0, 1.0)
	var mesh: ArrayMesh
	if steep_slope == null:
		mesh = LFHeightmap.build_mesh(data, samples, 1.0, 2.0, Color.GREEN, Color.GRAY)
	else:
		mesh = LFHeightmap.build_mesh(data, samples, 1.0, 2.0, Color.GREEN, Color.GRAY, steep_slope)
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]


func test_the_default_steep_slope_is_the_documented_constant() -> void:
	assert_eq(_surface_colors(null), _surface_colors(LFHeightmap.DEFAULT_STEEP_SLOPE))
	assert_ne(_surface_colors(null), _surface_colors(0.5), "the threshold changes the shading")


func test_slope_along_an_axis_with_a_single_sample_is_zero():
	var data := PackedFloat32Array([5.0])
	assert_eq(LFHeightmap.slope_at(data, 1, 1.0, 0, 0), 0.0)


func test_the_mesh_faces_up_with_two_triangles_per_cell():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 0.0, 2.0, 1.0)
	var mesh := LFHeightmap.build_mesh(data, 5, 1.0, 2.0, FLAT, STEEP)
	var arrays := mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 25, "one vertex per sample")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 4 * 4 * 6, "two triangles per cell")
	for normal in arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array:
		assert_almost_eq(normal, Vector3.UP, Vector3.ONE * 0.001)


func test_the_triangles_wind_clockwise_seen_from_above():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 0.0, 2.0, 1.0)
	var mesh := LFHeightmap.build_mesh(data, 5, 1.0, 2.0, FLAT, STEEP)
	var faces := mesh.get_faces()
	# Godot's front faces wind clockwise, so (c - a) x (b - a) points at the viewer.
	for i in range(0, faces.size(), 3):
		assert_gt((faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).y, 0.0, "front face up")


func test_a_centred_lattice_keeps_its_collider_at_the_origin():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 0.0, 2.0, 1.0)
	var body: StaticBody3D = autofree(LFHeightmap.build_body(data, 5, 1.0, 2.0, FLAT, STEEP))
	assert_eq((body.get_node(LFHeightmap.COLLISION_NODE_NAME) as CollisionShape3D).position, Vector3.ZERO)
	assert_eq(body.collision_layer, LFHeightmap.DEFAULT_COLLISION_LAYER)
	assert_not_null(body.get_node(LFHeightmap.MESH_NODE_NAME))


func test_overlapping_bounds_evaluate_the_shared_samples_again_with_the_same_result():
	var bounds: Array[Rect2] = [Rect2(-1, -1, 2, 2), Rect2(0, 0, 2, 2)]
	var data := LFHeightmap.lattice(func(x: float, z: float) -> float: return x + z, 2.0, 1.0, bounds)
	var full := LFHeightmap.lattice(func(x: float, z: float) -> float: return x + z, 2.0, 1.0)
	assert_eq(data[2 * 5 + 2], full[2 * 5 + 2], "inside both")
	assert_eq(data[4 * 5 + 4], full[4 * 5 + 4], "inside the second only")
	assert_eq(data[0], 0.0, "outside both")


func test_a_bad_spacing_or_extent_is_reported_and_gives_no_samples():
	for spacing: float in [0.0, -1.0, NAN, INF]:
		assert_eq(LFHeightmap.samples_for(10.0, spacing), 0, 'spacing %s' % spacing)
		assert_push_error('spacing')
	assert_eq(LFHeightmap.samples_for(NAN, 1.0), 0)
	assert_push_error('half_extent')
	assert_eq(LFHeightmap.samples_for(-1.0, 1.0), 0)
	assert_push_error('half_extent')
	assert_eq(LFHeightmap.samples_for(0.0, 1.0), 1, 'a zero extent is one sample')


func test_a_lattice_with_a_bad_spacing_is_empty():
	var data := LFHeightmap.lattice(func(_x: float, _z: float) -> float: return 1.0, 10.0, 0.0)
	assert_push_error('spacing')
	assert_eq(data.size(), 0)


func test_build_mesh_rejects_a_lattice_it_cannot_read():
	var one := LFHeightmap.build_mesh(PackedFloat32Array([0.0]), 1, 1.0, 0.0, FLAT, STEEP)
	assert_push_error('at least 2 samples')
	assert_eq(one.get_surface_count(), 0)
	var short := LFHeightmap.build_mesh(PackedFloat32Array([0.0, 1.0]), 3, 1.0, 1.0, FLAT, STEEP)
	assert_push_error('needs 9 heights')
	assert_eq(short.get_surface_count(), 0)
	var no_spacing := LFHeightmap.build_mesh(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), 2, 0.0, 1.0, FLAT, STEEP)
	assert_push_error('spacing')
	assert_eq(no_spacing.get_surface_count(), 0)


func test_build_body_rejects_a_lattice_it_cannot_read_with_an_empty_body():
	var body := LFHeightmap.build_body(PackedFloat32Array([0.0, 1.0]), 3, 1.0, 1.0, FLAT, STEEP)
	assert_push_error('needs 9 heights')
	assert_eq(body.get_child_count(), 0)
	body.free()


func test_a_steep_slope_of_zero_is_reported_instead_of_colouring_nan():
	var mesh := LFHeightmap.build_mesh(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), 2, 1.0, 0.5, FLAT, STEEP, 0.0)
	assert_push_error('steep_slope')
	assert_eq(mesh.get_surface_count(), 0)
