shader_type canvas_item;

// Only a plus-shaped area of the texture is drawn; its arms grow from the centre.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Half the thickness of each arm, in UV units.
uniform float arm_half_thickness : hint_range(0.0, 0.5) = 0.15;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 p = (UV - 0.5) * 2.0;
	bool vertical = abs(p.x) <= arm_half_thickness && abs(p.y) <= progress;
	bool horizontal = abs(p.y) <= arm_half_thickness && abs(p.x) <= progress;
	color.a *= (vertical || horizontal) ? 1.0 : 0.0;
	COLOR = color;
}
