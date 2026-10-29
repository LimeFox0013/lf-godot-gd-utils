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
	// The burn front moves from below 0 to above 1 so 0 is intact and 1 is gone.
	float front = amount * (1.0 + edge_width);
	float keep = smoothstep(front - edge_width, front, noise);
	float edge = (1.0 - smoothstep(front, front + edge_width, noise)) * smoothstep(0.0, 0.01, amount);
	COLOR = vec4(mix(sprite.rgb, edge_color.rgb, edge), sprite.a * keep);
}
