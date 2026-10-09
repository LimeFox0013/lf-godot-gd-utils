extends GutTest

## Uses lf_layout_control as the target component — it has a real .tscn at
## the naming-convention path LFComponents resolves against.

func test_create_component_instantiates_by_naming_convention_and_parents_it():
	var parent = add_child_autofree(Node.new())

	var comp = LFComponents.create_component("layout_control", parent)

	assert_true(comp is LFLayoutControl)
	assert_eq(comp.get_parent(), parent)


func test_a_component_without_a_scene_reports_and_returns_null():
	var parent = add_child_autofree(Node.new())

	var comp = LFComponents.create_component("no_such_component", parent)

	assert_push_error("has no scene")
	assert_null(comp)
	assert_eq(parent.get_child_count(), 0)


func test_a_parent_in_the_tree_has_the_components_ready_run_on_return():
	var parent = add_child_autofree(Node.new())

	var comp = LFComponents.create_component("layout_control", parent)

	assert_true(comp.is_node_ready(), "no await needed: _ready() already ran")
	assert_eq(comp.mouse_filter, Control.MOUSE_FILTER_IGNORE, "its tree-entry setup has been applied")


func test_init_component_returns_an_unparented_instance():
	var comp = LFComponents.init_component("control_out")

	assert_true(comp is LFControlOut)
	assert_null(comp.get_parent())
	comp.free()


func test_component_scenes_resolve_next_to_this_scripts_own_folder():
	var dir := LFComponents.components_dir()

	var own_folder: String = (LFComponents as Script).resource_path.get_base_dir()
	assert_eq(dir, own_folder.get_base_dir() + "/", "the base is the parent of the folder lf_components.gd lives in")
	assert_true(DirAccess.dir_exists_absolute(dir + "lf_layout_control"))


func test_a_parent_outside_the_tree_gets_the_component_before_its_ready():
	var parent = Node.new()

	var comp = LFComponents.create_component("layout_control", parent)

	assert_eq(comp.get_parent(), parent)
	assert_false(comp.is_node_ready(), "_ready() runs only once the parent enters the tree")
	parent.free()


func test_a_null_parent_reports_and_creates_nothing():
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var comp = LFComponents.create_component("layout_control", null)

	assert_null(comp)
	assert_push_error("parent")
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans_before, "no instance is left behind")


func test_a_name_that_is_not_a_plain_identifier_is_rejected():
	var comp = LFComponents.init_component("../lf_components")

	assert_null(comp)
	assert_push_error("not a component name")


func test_a_component_folder_without_a_scene_reports_and_returns_null():
	assert_true(DirAccess.dir_exists_absolute(LFComponents.components_dir() + "lf_bar_chart"), "the folder exists, it just has no .tscn")

	var comp = LFComponents.init_component("bar_chart")

	assert_null(comp)
	assert_push_error("has no scene")


func test_an_empty_name_is_rejected():
	assert_null(LFComponents.init_component(""))
	assert_push_error("not a component name")
