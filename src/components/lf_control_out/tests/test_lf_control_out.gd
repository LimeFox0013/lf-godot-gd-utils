extends GutTest

## The registry is process-wide static state, so every test below uses a registry id
## unique to itself to avoid cross-test collisions.


func _out_with_label(id: String) -> LFControlOut:
	var out = LFControlOut.new()
	out.registry_id = id
	var label = Label.new()
	out.add_child(label)
	out.label = label
	return out


func test_set_prop_writes_into_a_registered_control_outs_label():
	var out = LFControlOut.new()
	out.registry_id = "io-writes"
	var label = Label.new()
	out.add_child(label)
	out.label = label
	add_child_autofree(out)

	LFControlOut.set_prop("io-writes", "hello")

	assert_eq(label.text, "hello")


func test_set_prop_is_a_noop_when_the_registered_entry_is_not_a_control_out():
	var plain = LFControl.new()
	plain.registry_id = "io-noop-target"
	add_child_autofree(plain)

	# Must not error even though "io-noop-target" resolves to a plain LFControl.
	LFControlOut.set_prop("io-noop-target", "hello")

	assert_eq(get_errors().size(), 0, "a non-LFControlOut entry is skipped without any error or warning")
	assert_push_warning_count(0)
	assert_push_error_count(0)
	assert_engine_error_count(0)


func test_set_prop_with_an_unknown_id_is_a_silent_noop():
	LFControlOut.set_prop("io-never-registered", "hello")

	assert_eq(get_errors().size(), 0, "an unknown id is skipped without any error or warning")
	assert_push_warning_count(0)
	assert_push_error_count(0)
	assert_engine_error_count(0)


func test_set_prop_on_a_control_out_without_a_label_warns_instead_of_crashing():
	var out = LFControlOut.new()
	out.registry_id = "io-no-label"
	add_child_autofree(out)

	LFControlOut.set_prop("io-no-label", "hello")

	assert_push_warning("label", "a missing label is reported as a warning")
	assert_engine_error_count(0, "a missing label must not raise a script error")


func test_set_prop_on_a_control_out_whose_label_was_freed_warns_instead_of_crashing():
	var out = add_child_autofree(_out_with_label("io-freed-label"))
	out.label.free()

	LFControlOut.set_prop("io-freed-label", "hello")

	assert_push_warning("label")
	assert_engine_error_count(0)


func test_the_packaged_scene_attaches_the_control_out_script():
	var node = load(_module_dir().path_join("lf_control_out.tscn")).instantiate()
	assert_true(node is LFControlOut, "the scene must attach its LFControlOut script")
	node.free()


func test_set_prop_reaches_the_older_holder_once_the_newer_one_leaves():
	var older = add_child_autofree(_out_with_label("io-shadowed"))
	var newer = _out_with_label("io-shadowed")
	add_child(newer)
	remove_child(newer)

	LFControlOut.set_prop("io-shadowed", "still here")

	assert_eq(older.label.text, "still here")
	assert_eq(newer.label.text, "", "the holder that left is not written")
	newer.free()


func test_set_prop_writes_only_into_the_holder_in_the_given_viewport():
	var sub_viewport = add_child_autofree(SubViewport.new())
	var in_root = add_child_autofree(_out_with_label("io-per-viewport"))
	var in_sub = _out_with_label("io-per-viewport")
	sub_viewport.add_child(in_sub)

	LFControlOut.set_prop("io-per-viewport", "root text", get_viewport())

	assert_eq(in_root.label.text, "root text")
	assert_eq(in_sub.label.text, "")


func test_the_packaged_scene_wires_a_label_that_fills_the_control():
	var holder = add_child_autofree(Control.new())
	holder.size = Vector2(200, 50)
	var node: LFControlOut = load(_module_dir().path_join("lf_control_out.tscn")).instantiate()
	holder.add_child(node)

	assert_not_null(node.label, "the scene's Label is wired to the label export")
	assert_eq(node.label.get_parent(), node)
	assert_eq(node.label.size, Vector2(200, 50), "the label follows the control's rect")


## The module folder, wherever the library is installed.
func _module_dir() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()
