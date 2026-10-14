shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley;

// The texture layer comes from each instance's custom data (red channel), as
// LFMultiMeshScatter writes it.
uniform sampler2DArray textureArray : source_color;
uniform float alphaCutoff = 0.5;

varying flat float vLayer;

void vertex() {
	vLayer = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec4 col = texture(textureArray, vec3(UV, vLayer));

	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALBEDO = col.rgb;
	ALPHA = col.a;

	if (ALPHA < alphaCutoff) discard;
}
