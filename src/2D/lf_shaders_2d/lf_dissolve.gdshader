shader_type canvas_item;

// Burns or dissolves the sprite away following a noise texture.
uniform sampler2D noise_texture;
// 0 = intact, 1 = gone.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.3, 0.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.1) = 0.05;

void fragment() {
	vec4 sprite = texture(TEXTURE, UV);
	float noise = texture(noise_texture, UV).r;
	float gone = smoothstep(amount - edge_width, amount, noise);
	float edge = smoothstep(amount, amount + edge_width, noise);
	COLOR = vec4(mix(sprite.rgb, edge_color.rgb, edge), sprite.a * (1.0 - gone));
}
