extends GutTest


func _uniforms(shader: Shader) -> Dictionary:
	var found := {}
	for uniform in shader.get_shader_uniform_list():
		found[uniform['name']] = uniform['type']
	return found


func test_the_layered_cutout_is_a_spatial_shader_with_two_uniforms():
	var material := LFShaders3D.layered_cutout(null)
	assert_true(material.shader.code.begins_with('shader_type spatial;'))
	assert_eq(_uniforms(material.shader), {
		LFShaders3D.PARAM_TEXTURE_ARRAY: TYPE_OBJECT,
		LFShaders3D.PARAM_ALPHA_CUTOFF: TYPE_FLOAT,
	})


func test_the_shader_default_cutoff_matches_the_constant():
	var code := LFShaders3D.layered_cutout(null).shader.code
	var found := RegEx.create_from_string('uniform float alphaCutoff = ([0-9.]+);').search(code)
	assert_not_null(found)
	assert_eq(found.get_string(1).to_float(), LFShaders3D.DEFAULT_ALPHA_CUTOFF)


func test_a_material_carries_the_layers_and_the_cutoff():
	var layers := Texture2DArray.new()
	var material := LFShaders3D.layered_cutout(layers, 0.25)
	assert_eq(material.get_shader_parameter(LFShaders3D.PARAM_TEXTURE_ARRAY), layers)
	assert_eq(material.get_shader_parameter(LFShaders3D.PARAM_ALPHA_CUTOFF), 0.25)


func test_the_cutoff_is_clamped():
	assert_eq(LFShaders3D.layered_cutout(null, 5.0).get_shader_parameter(LFShaders3D.PARAM_ALPHA_CUTOFF), 1.0)
	assert_eq(LFShaders3D.layered_cutout(null, -1.0).get_shader_parameter(LFShaders3D.PARAM_ALPHA_CUTOFF), 0.0)


func test_a_non_finite_cutoff_gives_no_material():
	assert_null(LFShaders3D.layered_cutout(null, NAN))
	assert_push_error('finite')


func test_materials_share_one_compiled_shader_but_not_their_parameters():
	var first := LFShaders3D.layered_cutout(null, 0.2)
	var second := LFShaders3D.layered_cutout(null, 0.8)
	assert_same(first.shader, second.shader)
	assert_eq(first.get_shader_parameter(LFShaders3D.PARAM_ALPHA_CUTOFF), 0.2)
