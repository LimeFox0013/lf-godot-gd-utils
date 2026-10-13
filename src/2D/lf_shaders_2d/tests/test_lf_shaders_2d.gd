extends GutTest


func test_every_material_compiles_to_a_canvas_item_shader():
	var materials: Array[ShaderMaterial] = [
		LFShaders2D.sprite_outline(),
		LFShaders2D.screen_outline(),
		LFShaders2D.dissolve(null),
		LFShaders2D.darken(),
	]
	for material in materials:
		assert_not_null(material)
		assert_true(material.shader.code.begins_with('shader_type canvas_item;'))


func test_a_material_carries_the_given_parameters():
	var material := LFShaders2D.sprite_outline(Color.RED, 2.0)
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_OUTLINE_COLOR), Color.RED)
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_OUTLINE_WIDTH), 2.0)


func test_the_screen_outline_takes_the_colour_without_alpha():
	var material := LFShaders2D.screen_outline(Color(0.1, 0.2, 0.3, 0.5), 4)
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_OUTLINE_COLOR), Vector3(0.1, 0.2, 0.3))
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_OUTLINE_THICKNESS), 4)


func test_the_dissolve_keeps_its_noise_texture():
	var noise := NoiseTexture2D.new()
	var material := LFShaders2D.dissolve(noise, 0.25)
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_NOISE), noise)
	assert_eq(material.get_shader_parameter(LFShaders2D.PARAM_AMOUNT), 0.25)


func test_values_outside_the_shader_ranges_are_clamped():
	assert_eq(LFShaders2D.sprite_outline(Color.RED, 99.0).get_shader_parameter(LFShaders2D.PARAM_OUTLINE_WIDTH), LFShaders2D.MAX_OUTLINE_WIDTH)
	assert_eq(LFShaders2D.screen_outline(Color.RED, -3).get_shader_parameter(LFShaders2D.PARAM_OUTLINE_THICKNESS), 0)
	assert_eq(LFShaders2D.dissolve(null, 2.0, Color.RED, 5.0).get_shader_parameter(LFShaders2D.PARAM_EDGE_WIDTH), LFShaders2D.MAX_EDGE_WIDTH)
	assert_eq(LFShaders2D.darken(-1.0).get_shader_parameter(LFShaders2D.PARAM_DARKNESS), 0.0)


func test_a_non_finite_number_gives_no_material():
	assert_null(LFShaders2D.darken(NAN))
	assert_push_error('finite')
	assert_null(LFShaders2D.sprite_outline(Color.RED, INF))
	assert_push_error('finite')
	assert_null(LFShaders2D.dissolve(null, NAN))
	assert_push_error('finite')


func test_materials_share_one_compiled_shader_but_not_their_parameters():
	var first := LFShaders2D.darken(0.2)
	var second := LFShaders2D.darken(0.8)
	assert_same(first.shader, second.shader)
	assert_ne(first, second)
	assert_eq(first.get_shader_parameter(LFShaders2D.PARAM_DARKNESS), 0.2)
