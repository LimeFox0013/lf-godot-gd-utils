extends GutTest

func test_returns_the_projects_configured_viewport_size():
	var expected = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)
	assert_eq(LFUtils.get_project_screen_size(), expected)
