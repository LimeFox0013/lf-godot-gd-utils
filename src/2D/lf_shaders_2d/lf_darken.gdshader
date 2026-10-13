shader_type canvas_item;

// Multiplies the colour by 1 - darkness; alpha is kept.
uniform float darkness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	COLOR = vec4(color.rgb * (1.0 - darkness), color.a);
}
