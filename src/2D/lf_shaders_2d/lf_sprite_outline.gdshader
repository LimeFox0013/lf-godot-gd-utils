shader_type canvas_item;

// Draws an outline around the opaque part of the sprite's own texture.
uniform vec4 outline_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);
// In pixels of the texture.
uniform float outline_width : hint_range(0.0, 6.0) = 3.0;

void fragment() {
	float size = outline_width / float(textureSize(TEXTURE, 0).x);
	vec4 sprite = texture(TEXTURE, UV);
	float edge = -4.0 * sprite.a;
	edge += texture(TEXTURE, UV + vec2(size, 0.0)).a;
	edge += texture(TEXTURE, UV + vec2(-size, 0.0)).a;
	edge += texture(TEXTURE, UV + vec2(0.0, size)).a;
	edge += texture(TEXTURE, UV + vec2(0.0, -size)).a;
	vec4 mixed = mix(sprite, outline_color, clamp(edge, 0.0, 1.0));
	COLOR = vec4(mixed.rgb, clamp(abs(edge) + sprite.a, 0.0, 1.0));
}
