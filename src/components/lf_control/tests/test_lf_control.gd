extends GutTest

## The registry is process-wide static state, so every test below uses a registry id
## unique to itself to avoid cross-test collisions.


class SkipsSuperInExitTree extends LFControl:
	func _exit_tree() -> void:
		pass


class SkipsSuperInEnterTree extends LFControl:
	func _enter_tree() -> void:
		pass


func test_control_registers_itself_under_its_registry_id_on_entering_the_tree():
	var control = LFControl.new()
	control.registry_id = "core-registers"
	add_child_autofree(control)
	assert_same(LFControl.by_id("core-registers"), control)


func test_control_with_an_empty_registry_id_does_not_register():
	var control = LFControl.new()
	control.registry_id = ""
	add_child_autofree(control)
	assert_null(LFControl.by_id(""))


func test_by_id_with_an_unregistered_id_returns_null_not_an_error():
	assert_null(LFControl.by_id("core-never-registered-" + str(Time.get_ticks_usec())))
	assert_engine_error_count(0)


func test_get_center_pos_is_half_the_controls_size():
	var control = add_child_autofree(Control.new())
	control.size = Vector2(100, 60)
	assert_eq(LFControl.get_center_pos(control), Vector2(50, 30))


func test_a_control_leaving_the_tree_unregisters_itself():
	var control = LFControl.new()
	control.registry_id = "core-unregisters"
	add_child(control)

	remove_child(control)

	assert_null(LFControl.by_id("core-unregisters"), "a detached control must not stay reachable")
	control.free()


func test_leaving_the_tree_does_not_unregister_a_newer_holder_of_the_id():
	var older = LFControl.new()
	older.registry_id = "core-shared-id"
	add_child(older)
	var newer = LFControl.new()
	newer.registry_id = "core-shared-id"
	add_child_autofree(newer)

	remove_child(older)

	assert_same(LFControl.by_id("core-shared-id"), newer)
	older.free()


func test_a_reparented_control_is_still_registered():
	var first_parent = add_child_autofree(Node.new())
	var second_parent = add_child_autofree(Node.new())
	var control = LFControl.new()
	control.registry_id = "core-reparented"
	first_parent.add_child(control)

	control.reparent(second_parent)

	assert_same(LFControl.by_id("core-reparented"), control, "re-entering the tree must re-register")


func test_a_layout_control_re_registers_after_being_removed_and_added_again():
	var control = LFLayoutControl.new()
	control.registry_id = "core-layout-readded"
	add_child_autofree(control)

	remove_child(control)
	add_child(control)

	assert_same(LFControl.by_id("core-layout-readded"), control)


func test_center_on_viewport_accounts_for_the_controls_scale():
	var control = add_child_autofree(Control.new())
	control.position = Vector2(10, 20)
	control.size = Vector2(100, 60)
	control.scale = Vector2(2, 2)

	assert_eq(LFControl.get_center_pos_on_viewport(control), Vector2(110, 80), "a scaled control's center is the center of its scaled global rect")


func test_changing_registry_id_while_in_the_tree_re_registers_under_the_new_id():
	var control = LFControl.new()
	control.registry_id = "core-renamed-old"
	add_child_autofree(control)

	control.registry_id = "core-renamed-new"

	assert_same(LFControl.by_id("core-renamed-new"), control)
	assert_null(LFControl.by_id("core-renamed-old"), "the old id must no longer resolve")


func test_clearing_registry_id_while_in_the_tree_unregisters():
	var control = LFControl.new()
	control.registry_id = "core-cleared"
	add_child_autofree(control)

	control.registry_id = ""

	assert_null(LFControl.by_id("core-cleared"))


func test_renaming_does_not_drop_a_newer_holder_of_the_old_id():
	var older = LFControl.new()
	older.registry_id = "core-rename-shared"
	add_child_autofree(older)
	var newer = LFControl.new()
	newer.registry_id = "core-rename-shared"
	add_child_autofree(newer)

	older.registry_id = "core-rename-elsewhere"

	assert_same(LFControl.by_id("core-rename-shared"), newer)
	assert_same(LFControl.by_id("core-rename-elsewhere"), older)


func test_a_freed_control_is_no_longer_reachable():
	var control = LFControl.new()
	control.registry_id = "core-freed"
	add_child(control)

	control.free()

	assert_null(LFControl.by_id("core-freed"))


func test_the_older_holder_of_an_id_is_found_again_once_the_newer_one_leaves():
	var older = LFControl.new()
	older.registry_id = "core-shadowed"
	add_child_autofree(older)
	var newer = LFControl.new()
	newer.registry_id = "core-shadowed"
	add_child(newer)

	remove_child(newer)

	assert_same(LFControl.by_id("core-shadowed"), older, "the older holder is still in the tree, so it is found")
	newer.free()


func test_the_newest_holder_wins_while_several_share_an_id():
	var first = LFControl.new()
	first.registry_id = "core-three-holders"
	add_child_autofree(first)
	var second = LFControl.new()
	second.registry_id = "core-three-holders"
	add_child_autofree(second)
	var third = LFControl.new()
	third.registry_id = "core-three-holders"
	add_child(third)

	assert_same(LFControl.by_id("core-three-holders"), third)
	third.free()
	assert_same(LFControl.by_id("core-three-holders"), second)


func test_a_subclass_skipping_super_in_exit_tree_never_leaves_a_freed_node_behind():
	var control = SkipsSuperInExitTree.new()
	control.registry_id = "core-skips-exit-super"
	add_child(control)

	control.free()

	assert_null(LFControl.by_id("core-skips-exit-super"))
	assert_engine_error_count(0, "looking up the id must not raise an error")


func test_a_subclass_skipping_super_in_exit_tree_is_unregistered_when_removed():
	var control = SkipsSuperInExitTree.new()
	control.registry_id = "core-skips-exit-removed"
	add_child(control)

	remove_child(control)

	assert_null(LFControl.by_id("core-skips-exit-removed"))
	control.free()


func test_a_subclass_skipping_super_in_enter_tree_still_registers():
	var control = SkipsSuperInEnterTree.new()
	control.registry_id = "core-skips-enter-super"
	add_child_autofree(control)

	assert_same(LFControl.by_id("core-skips-enter-super"), control)


func test_the_same_id_resolves_per_viewport_when_one_is_given():
	var sub_viewport = add_child_autofree(SubViewport.new())
	var in_root = LFControl.new()
	in_root.registry_id = "core-per-viewport"
	add_child_autofree(in_root)
	var in_sub = LFControl.new()
	in_sub.registry_id = "core-per-viewport"
	sub_viewport.add_child(in_sub)

	assert_same(LFControl.by_id("core-per-viewport", get_viewport()), in_root)
	assert_same(LFControl.by_id("core-per-viewport", sub_viewport), in_sub)
	assert_same(LFControl.by_id("core-per-viewport"), in_sub, "without a viewport the newest holder anywhere wins")


func test_a_viewport_with_no_holder_of_the_id_gives_null():
	var sub_viewport = add_child_autofree(SubViewport.new())
	var in_root = LFControl.new()
	in_root.registry_id = "core-viewport-miss"
	add_child_autofree(in_root)

	assert_null(LFControl.by_id("core-viewport-miss", sub_viewport))


func test_center_on_viewport_is_the_on_screen_center_under_a_canvas_layer():
	var layer = add_child_autofree(CanvasLayer.new())
	layer.offset = Vector2(100, 0)
	layer.scale = Vector2(2, 2)
	var control = Control.new()
	control.position = Vector2(10, 10)
	control.size = Vector2(20, 20)
	layer.add_child(control)

	assert_eq(LFControl.get_center_pos_on_viewport(control), Vector2(140, 40))


func test_center_on_viewport_follows_a_rotated_control():
	var control = add_child_autofree(Control.new())
	control.position = Vector2(100, 100)
	control.size = Vector2(40, 20)
	control.rotation = PI * 0.5

	assert_almost_eq(LFControl.get_center_pos_on_viewport(control), Vector2(90, 120), Vector2(0.001, 0.001), "the center turns with the control around its top-left")


func _box(parent: Node, at: Vector2, name := '') -> Control:
	var control := Control.new()
	if name != '':
		control.name = name
	control.position = at
	control.size = Vector2(80, 20)
	parent.add_child(control)
	return control


func test_sort_reading_order_goes_row_by_row_then_left_to_right():
	var root: Control = add_child_autofree(Control.new())
	var c := _box(root, Vector2(20, 200), 'C')
	var b := _box(root, Vector2(300, 22), 'B')
	var a := _box(root, Vector2(20, 20), 'A')
	var input := [c, b, a]

	var sorted := LFControl.sort_reading_order(input, 24.0)

	assert_eq(sorted, [a, b, c], 'B sits 2 px lower than A but on the same row')
	assert_eq(input, [c, b, a], 'the input is left alone')


func test_sort_reading_order_without_tolerance_sorts_by_top_first():
	var root: Control = add_child_autofree(Control.new())
	var right_higher := _box(root, Vector2(300, 20))
	var left_lower := _box(root, Vector2(20, 22))

	assert_eq(LFControl.sort_reading_order([left_lower, right_higher]), [right_higher, left_lower])


func test_sort_reading_order_skips_non_controls():
	var root: Control = add_child_autofree(Control.new())
	var a := _box(root, Vector2.ZERO)

	assert_eq(LFControl.sort_reading_order([null, a, 'x'], 10.0), [a])


func test_place_beside_goes_right_when_it_fits():
	var at := LFControl.place_beside(Rect2(100, 50, 40, 20), Vector2(200, 100), Vector2(800, 600), 12.0)

	assert_eq(at, Vector2(152, 50))


func test_place_beside_flips_left_when_the_right_is_full():
	var at := LFControl.place_beside(Rect2(700, 50, 40, 20), Vector2(200, 100), Vector2(800, 600), 12.0)

	assert_eq(at, Vector2(488, 50))


func test_place_beside_clamps_to_the_area_edges():
	assert_eq(LFControl.place_beside(Rect2(700, 560, 40, 20), Vector2(200, 100), Vector2(800, 600), 12.0).y, 500.0, 'pulled up from the bottom')
	assert_eq(LFControl.place_beside(Rect2(700, -30, 40, 20), Vector2(200, 100), Vector2(800, 600)).y, 0.0, 'pushed down from the top')
	assert_eq(LFControl.place_beside(Rect2(10, 10, 700, 20), Vector2(200, 100), Vector2(800, 600), 12.0).x, 0.0, 'no room either side: clamped to the left edge')
	assert_eq(LFControl.place_beside(Rect2(10, 10, 40, 20), Vector2(200, 700), Vector2(800, 600)).y, 0.0, 'taller than the area: top-aligned')


func test_sort_reading_order_skips_a_freed_control_without_an_error():
	var root: Control = add_child_autofree(Control.new())
	var a := _box(root, Vector2.ZERO)
	var gone := _box(root, Vector2(0, 50))
	gone.free()

	assert_eq(LFControl.sort_reading_order([gone, a]), [a])
	assert_engine_error_count(0)


## Tops 0, 8 and 16 with a 10 px tolerance: 0 and 8 share a row, 16 is too far from the
## row's top and starts the next one, whatever their x order.
func test_sort_reading_order_groups_ragged_rows_by_the_rows_top_control():
	var root: Control = add_child_autofree(Control.new())
	var high_right := _box(root, Vector2(300, 0))
	var mid_middle := _box(root, Vector2(150, 8))
	var low_left := _box(root, Vector2(0, 16))

	var orders := [
		[high_right, mid_middle, low_left], [high_right, low_left, mid_middle],
		[mid_middle, high_right, low_left], [mid_middle, low_left, high_right],
		[low_left, high_right, mid_middle], [low_left, mid_middle, high_right],
	]

	for order: Array in orders:
		assert_eq(LFControl.sort_reading_order(order, 10.0), [mid_middle, high_right, low_left])
	assert_engine_error_count(0)


func test_get_canvas_rect_goes_through_a_canvas_layer():
	var canvas_layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	canvas_layer.offset = Vector2(500, 10)
	canvas_layer.scale = Vector2(2, 2)
	var box := _box(canvas_layer, Vector2(20, 20), 'Layered')

	assert_eq(LFControl.get_canvas_rect(box), Rect2(Vector2(540, 50), box.size * 2.0))
	assert_eq(box.get_global_rect().position, Vector2(20, 20), 'the global rect alone ignores the layer')


func test_sort_reading_order_reads_controls_where_they_are_drawn():
	var root: Control = add_child_autofree(Control.new())
	var canvas_layer: CanvasLayer = add_child_autofree(CanvasLayer.new())
	canvas_layer.offset = Vector2(500, 0)
	var shifted := _box(canvas_layer, Vector2(20, 20), 'Shifted')
	var plain := _box(root, Vector2(300, 20), 'Plain')

	assert_eq(LFControl.sort_reading_order([shifted, plain], 10.0), [plain, shifted], 'drawn at x 520, right of the plain one')


func test_the_packaged_scene_is_a_full_rect_lf_control():
	var node: Control = load(_scene_dir().path_join("lf_control.tscn")).instantiate()
	assert_true(node is LFControl, "the scene must attach its LFControl script")
	assert_eq(node.anchor_right, 1.0)
	assert_eq(node.anchor_bottom, 1.0)
	node.free()


func test_get_canvas_rect_equals_the_global_rect_on_the_plain_canvas():
	var root: Control = add_child_autofree(Control.new())
	var box := _box(root, Vector2(30, 40), 'Plain')
	box.size = Vector2(70, 20)

	assert_eq(LFControl.get_canvas_rect(box), box.get_global_rect())


func test_place_beside_keeps_a_box_that_exactly_fits_on_the_right():
	var at := LFControl.place_beside(Rect2(100, 50, 40, 20), Vector2(200, 100), Vector2(352, 600), 12.0)

	assert_eq(at, Vector2(152, 50), "ending exactly on the area's right edge still fits")


func test_an_id_reused_after_all_its_holders_left_resolves_to_the_new_holder():
	var first: LFControl = LFControl.new()
	first.registry_id = "core-reused-after-empty"
	add_child(first)
	first.free()
	assert_null(LFControl.by_id("core-reused-after-empty"))

	var second: LFControl = LFControl.new()
	second.registry_id = "core-reused-after-empty"
	add_child_autofree(second)

	assert_same(LFControl.by_id("core-reused-after-empty"), second)


func test_pin_to_a_right_bottom_corner_grows_inward():
	var root: Control = add_child_autofree(Control.new())
	root.size = Vector2(400, 300)
	var box := _box(root, Vector2.ZERO, 'Pinned')
	box.custom_minimum_size = Vector2(50, 20)

	LFControl.pin(box, Control.PRESET_BOTTOM_RIGHT, 10)

	assert_eq(box.grow_horizontal, Control.GROW_DIRECTION_BEGIN)
	assert_eq(box.grow_vertical, Control.GROW_DIRECTION_BEGIN)
	assert_eq(box.get_rect().end, Vector2(390, 290))


func test_pin_centred_presets_grow_both_ways_and_left_top_grow_outward():
	var root: Control = add_child_autofree(Control.new())
	var centred := _box(root, Vector2.ZERO, 'Centred')
	var corner := _box(root, Vector2.ZERO, 'Corner')

	LFControl.pin(centred, Control.PRESET_CENTER)
	LFControl.pin(corner, Control.PRESET_TOP_LEFT)

	assert_eq(centred.grow_horizontal, Control.GROW_DIRECTION_BOTH)
	assert_eq(centred.grow_vertical, Control.GROW_DIRECTION_BOTH)
	assert_eq(corner.grow_horizontal, Control.GROW_DIRECTION_END)
	assert_eq(corner.grow_vertical, Control.GROW_DIRECTION_END)


func test_pin_offset_nudges_the_final_position():
	var root: Control = add_child_autofree(Control.new())
	root.size = Vector2(400, 300)
	var box := _box(root, Vector2.ZERO, 'Nudged')
	LFControl.pin(box, Control.PRESET_TOP_LEFT)
	var before := box.position

	LFControl.pin(box, Control.PRESET_TOP_LEFT, 0, Vector2(5, -3))

	assert_eq(box.position, before + Vector2(5, -3))


func _scene_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()
