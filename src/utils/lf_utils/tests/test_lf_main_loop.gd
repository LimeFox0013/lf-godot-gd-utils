extends GutTest

func test_main_loop_is_the_engine_main_loop():
	assert_same(LFUtils.main_loop, Engine.get_main_loop())


func test_tree_root_is_the_running_scene_tree():
	assert_same(LFUtils.tree_root, get_tree())
