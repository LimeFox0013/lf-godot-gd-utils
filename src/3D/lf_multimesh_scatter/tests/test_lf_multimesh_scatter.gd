extends GutTest

## The size of the test area, in world units.
const AREA_SIZE := Vector2(10.0, 4.0)
## Where the test area sits.
const AREA_POSITION := Vector3(3.0, 2.0, -5.0)
## A seed for the tests that need a repeatable roll.
const SEED := 42


func _make_area(parent: Node3D) -> MeshInstance3D:
	var area := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = AREA_SIZE
	area.mesh = plane
	parent.add_child(area)
	area.position = AREA_POSITION
	return area


func _make_scatter(density := 2.0) -> LFMultiMeshScatter:
	var root: Node3D = add_child_autofree(Node3D.new())
	var scatter := LFMultiMeshScatter.new()
	scatter.multimesh = MultiMesh.new()
	scatter.multimesh.mesh = BoxMesh.new()
	scatter.area = _make_area(root)
	scatter.density = density
	scatter.scatter_on_ready = false
	root.add_child(scatter)
	return scatter


func _rng(seed_value := SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# The headless renderer keeps no multimesh buffer, so what is placed is checked through
# `place`, and the node through the counts it sets.

func test_it_places_density_times_area_instances():
	var scatter := _make_scatter(2.0)
	watch_signals(scatter)
	assert_eq(scatter.scatter(), 80)
	assert_eq(scatter.multimesh.instance_count, 80)
	assert_eq(scatter.multimesh.visible_instance_count, 80)
	assert_true(scatter.multimesh.use_custom_data)
	assert_signal_emitted_with_parameters(scatter, "scattered", [80])


func test_it_places_at_least_one_instance():
	assert_eq(_make_scatter(0.0).scatter(), 1)


func test_scattering_again_replaces_the_instances():
	var scatter := _make_scatter(1.0)
	scatter.scatter()
	scatter.density = 2.0
	assert_eq(scatter.scatter(), 80)
	assert_eq(scatter.multimesh.instance_count, 80)


func test_it_scatters_on_ready_by_default():
	var root: Node3D = add_child_autofree(Node3D.new())
	var scatter := LFMultiMeshScatter.new()
	scatter.multimesh = MultiMesh.new()
	scatter.multimesh.mesh = BoxMesh.new()
	scatter.area = _make_area(root)
	root.add_child(scatter)
	assert_eq(scatter.multimesh.instance_count, 40)


func test_missing_pieces_are_reported_and_place_nothing():
	var scatter := _make_scatter()
	scatter.area = null
	assert_eq(scatter.scatter(), 0)
	assert_push_error('LFMultiMeshScatter')
	scatter.area = _make_area(scatter)
	scatter.multimesh.mesh = null
	assert_eq(scatter.scatter(), 0)
	assert_push_error('LFMultiMeshScatter')
	scatter.multimesh.mesh = BoxMesh.new()
	scatter.area.mesh = null
	assert_eq(scatter.scatter(), 0)
	assert_push_error('LFMultiMeshScatter')


func test_layer_count_never_drops_below_one():
	var scatter := _make_scatter()
	scatter.layer_count = -4
	assert_eq(scatter.layer_count, 1)


func test_place_keeps_every_instance_on_the_area():
	var placement := LFMultiMeshScatter.place(AREA_SIZE, 200, _rng(), Transform3D(Basis.IDENTITY, AREA_POSITION), 0.5)
	assert_eq(placement.transforms.size(), 200)
	for at in placement.transforms:
		assert_between(at.origin.x, AREA_POSITION.x - 5.0, AREA_POSITION.x + 5.0)
		assert_between(at.origin.z, AREA_POSITION.z - 2.0, AREA_POSITION.z + 2.0)
		assert_almost_eq(at.origin.y, AREA_POSITION.y + 0.5, 0.0001)


func test_place_covers_the_whole_area():
	var placement := LFMultiMeshScatter.place(AREA_SIZE, 400, _rng())
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for at in placement.transforms:
		low = Vector2(minf(low.x, at.origin.x), minf(low.y, at.origin.z))
		high = Vector2(maxf(high.x, at.origin.x), maxf(high.y, at.origin.z))
	assert_lt(low.x, -4.0)
	assert_gt(high.x, 4.0)
	assert_lt(low.y, -1.5)
	assert_gt(high.y, 1.5)


func test_place_goes_through_the_given_transform():
	var turned := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) # the width now runs along Z
	for at in LFMultiMeshScatter.place(AREA_SIZE, 100, _rng(), turned).transforms:
		assert_between(at.origin.x, -2.0, 2.0)
		assert_between(at.origin.z, -5.0, 5.0)


func test_layers_are_whole_numbers_below_the_layer_count():
	var placement := LFMultiMeshScatter.place(AREA_SIZE, 200, _rng(), Transform3D.IDENTITY, 0.0, Vector2.ONE, 3)
	assert_eq(placement.layers.size(), 200)
	var seen := {}
	for layer in placement.layers:
		assert_between(layer, 0, 2)
		seen[layer] = true
	assert_eq(seen.size(), 3, "all three layers are used")


func test_one_layer_means_layer_zero():
	for layer in LFMultiMeshScatter.place(AREA_SIZE, 20, _rng()).layers:
		assert_eq(layer, 0)
	for layer in LFMultiMeshScatter.place(AREA_SIZE, 20, _rng(), Transform3D.IDENTITY, 0.0, Vector2.ONE, -3).layers:
		assert_eq(layer, 0)


func test_sizes_stay_within_the_scale_range():
	var smallest := INF
	var largest := 0.0
	for at in LFMultiMeshScatter.place(AREA_SIZE, 300, _rng(), Transform3D.IDENTITY, 0.0, Vector2(0.5, 1.5)).transforms:
		var size := at.basis.x.length()
		smallest = minf(smallest, size)
		largest = maxf(largest, size)
	assert_gte(smallest, 0.5 - 0.0001)
	assert_lte(largest, 1.5 + 0.0001)
	assert_gt(largest - smallest, 0.5, "sizes vary")


func test_a_reversed_scale_range_still_works():
	for at in LFMultiMeshScatter.place(AREA_SIZE, 50, _rng(), Transform3D.IDENTITY, 0.0, Vector2(2.0, 1.0)).transforms:
		assert_between(at.basis.x.length(), 1.0 - 0.0001, 2.0 + 0.0001)


func test_the_same_seed_places_the_same_way():
	var first := LFMultiMeshScatter.place(AREA_SIZE, 30, _rng(), Transform3D.IDENTITY, 0.0, Vector2(1.0, 2.0), 4)
	var second := LFMultiMeshScatter.place(AREA_SIZE, 30, _rng(), Transform3D.IDENTITY, 0.0, Vector2(1.0, 2.0), 4)
	assert_eq(first.transforms, second.transforms)
	assert_eq(first.layers, second.layers)
	var other := LFMultiMeshScatter.place(AREA_SIZE, 30, _rng(SEED + 1))
	assert_ne(first.transforms[0], other.transforms[0])


func test_a_count_of_zero_or_less_places_nothing():
	assert_eq(LFMultiMeshScatter.place(AREA_SIZE, 0, _rng()).transforms.size(), 0)
	assert_eq(LFMultiMeshScatter.place(AREA_SIZE, -5, _rng()).transforms.size(), 0)


func test_plane_size_reads_a_plane_or_the_bounds_of_other_meshes():
	var holder: Node3D = add_child_autofree(Node3D.new())
	var area := _make_area(holder)
	assert_eq(LFMultiMeshScatter.plane_size_xz(area), AREA_SIZE)
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 9.0, 7.0)
	area.mesh = box
	assert_eq(LFMultiMeshScatter.plane_size_xz(area), Vector2(3.0, 7.0))
	assert_eq(LFMultiMeshScatter.plane_size_xz(null), Vector2.ZERO)
	area.mesh = null
	assert_eq(LFMultiMeshScatter.plane_size_xz(area), Vector2.ZERO)


func test_outside_the_tree_it_reports_and_places_nothing():
	var scatter := LFMultiMeshScatter.new()
	scatter.multimesh = MultiMesh.new()
	scatter.multimesh.mesh = BoxMesh.new()
	var root: Node3D = add_child_autofree(Node3D.new())
	scatter.area = _make_area(root)
	scatter.scatter_on_ready = false
	assert_eq(scatter.scatter(), 0)
	assert_push_error('LFMultiMeshScatter')
	scatter.free()
