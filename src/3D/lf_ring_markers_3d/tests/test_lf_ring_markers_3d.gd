extends GutTest

var markers: LFRingMarkers3D


func before_each():
	markers = LFRingMarkers3D.new(4.0, 0.5, Color.RED, 0.1)
	add_child_autofree(markers)


func test_starts_hidden_with_no_rings():
	assert_false(markers.visible)
	assert_eq(markers.shown_count(), 0)


func test_display_shows_one_ring_per_position_lifted_above_it():
	var first := Vector3(1, 0, 2)

	markers.display([first, Vector3(5, 0, 5), Vector3(-4, 0, 3)])
	markers.display([first])

	assert_eq(markers.get_child_count(), 3)
	assert_eq(markers.shown_count(), 1)
	assert_eq((markers.get_child(0) as MeshInstance3D).position, first + Vector3(0, 0.1, 0))


func test_every_ring_shares_one_mesh_and_material_of_the_given_size():
	markers.display([Vector3.ZERO, Vector3(5, 0, 5)])

	var first: MeshInstance3D = markers.get_child(0)
	var second: MeshInstance3D = markers.get_child(1)
	assert_same(second.mesh, first.mesh)
	assert_same(second.material_override, first.material_override)
	assert_eq([(first.mesh as TorusMesh).inner_radius, (first.mesh as TorusMesh).outer_radius], [3.5, 4.0])
	assert_eq((first.material_override as StandardMaterial3D).albedo_color, Color.RED)


func test_growing_again_reuses_the_hidden_rings():
	markers.display([Vector3.ZERO, Vector3(5, 0, 5), Vector3(9, 0, 9)])
	markers.display([Vector3.ZERO])
	markers.visible = false
	assert_eq(markers.shown_count(), 0)

	markers.display([Vector3.ZERO, Vector3(1, 0, 1), Vector3(2, 0, 2)])

	assert_eq(markers.get_child_count(), 3)
	assert_eq(markers.shown_count(), 3)
