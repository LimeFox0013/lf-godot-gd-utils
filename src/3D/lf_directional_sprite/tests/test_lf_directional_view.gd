extends GutTest

const View := LFDirectionalView.View


func test_a_viewer_the_character_faces_sees_the_front():
	assert_eq(LFDirectionalView.resolve(Vector2.UP, Vector2.UP), View.FRONT)


func test_a_viewer_behind_the_character_sees_the_back():
	assert_eq(LFDirectionalView.resolve(Vector2.UP, Vector2.DOWN), View.BACK)


func test_a_viewer_90_degrees_one_way_sees_side_r():
	assert_eq(LFDirectionalView.resolve(Vector2.UP, Vector2.RIGHT), View.SIDE_R)


func test_a_viewer_90_degrees_the_other_way_sees_side_l():
	assert_eq(LFDirectionalView.resolve(Vector2.UP, Vector2.LEFT), View.SIDE_L)


func test_front_and_back_wedges_include_their_45_degree_boundaries():
	var facing := Vector2.UP
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(45.0))), View.FRONT)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(135.0))), View.BACK)


func test_the_four_wedges_are_equal_90_degree_quadrants():
	var facing := Vector2.UP
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(45.5))), View.SIDE_R)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(134.5))), View.SIDE_R)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(-45.5))), View.SIDE_L)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(-134.5))), View.SIDE_L)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(-45.0))), View.FRONT)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(-135.0))), View.BACK)


func test_a_wider_front_wedge_moves_the_boundaries():
	var facing := Vector2.UP
	var at_60 := Vector2.UP.rotated(deg_to_rad(60.0))
	assert_eq(LFDirectionalView.resolve(facing, at_60), View.SIDE_R)
	assert_eq(LFDirectionalView.resolve(facing, at_60, 60.0), View.FRONT)
	assert_eq(LFDirectionalView.resolve(facing, Vector2.UP.rotated(deg_to_rad(121.0)), 60.0), View.BACK)


func test_resolution_depends_only_on_the_relative_angle():
	var facing := Vector2.RIGHT
	assert_eq(LFDirectionalView.resolve(facing, Vector2.RIGHT.rotated(deg_to_rad(170.0))), View.BACK)


func test_side_r_is_never_mirrored():
	assert_false(LFDirectionalView.is_mirrored(View.SIDE_R, true))


func test_side_l_is_mirrored_only_when_sides_are_mirrored():
	assert_true(LFDirectionalView.is_mirrored(View.SIDE_L, true))
	assert_false(LFDirectionalView.is_mirrored(View.SIDE_L, false))


func test_segments_name_each_view():
	assert_eq(LFDirectionalView.segment(View.FRONT), "front")
	assert_eq(LFDirectionalView.segment(View.BACK), "back")
	assert_eq(LFDirectionalView.segment(View.SIDE_L), "side")
	assert_eq(LFDirectionalView.segment(View.SIDE_R, false), "side_r")


func test_animation_name_combines_the_view_and_the_state():
	assert_eq(LFDirectionalView.animation_name(View.FRONT, &"idle"), "front_idle")
	assert_eq(LFDirectionalView.animation_name(View.BACK, &"walk"), "back_walk")
	assert_eq(LFDirectionalView.animation_name(View.FRONT, &"action_a"), "front_action_a")
	assert_eq(LFDirectionalView.animation_name(View.BACK, &"fall"), "back_fall")


func test_mirrored_sides_share_one_animation():
	assert_eq(LFDirectionalView.animation_name(View.SIDE_L, &"walk"), "side_walk")
	assert_eq(LFDirectionalView.animation_name(View.SIDE_R, &"walk"), "side_walk")


func test_authored_sides_keep_distinct_animations():
	assert_eq(LFDirectionalView.animation_name(View.SIDE_L, &"walk", false), "side_l_walk")
	assert_eq(LFDirectionalView.animation_name(View.SIDE_R, &"walk", false), "side_r_walk")


func test_the_death_animation_is_named_per_view_mirrored():
	assert_eq(LFDirectionalView.animation_name(View.FRONT, &"die"), "front_die")
	assert_eq(LFDirectionalView.animation_name(View.BACK, &"die"), "back_die")
	assert_eq(LFDirectionalView.animation_name(View.SIDE_L, &"die"), "side_die")
	assert_eq(LFDirectionalView.animation_name(View.SIDE_R, &"die"), "side_die")


func test_the_death_animation_is_named_per_side_when_sides_are_authored():
	assert_eq(LFDirectionalView.animation_name(View.SIDE_L, &"die", false), "side_l_die")
	assert_eq(LFDirectionalView.animation_name(View.SIDE_R, &"die", false), "side_r_die")


func test_a_zero_facing_or_viewer_direction_counts_as_front():
	assert_eq(LFDirectionalView.resolve(Vector2.ZERO, Vector2.DOWN), View.FRONT)
	assert_eq(LFDirectionalView.resolve(Vector2.UP, Vector2.ZERO), View.FRONT)


func test_the_default_front_half_width_is_the_documented_constant() -> void:
	var facing := Vector2(0, 1)
	var just_inside := facing.rotated(deg_to_rad(LFDirectionalView.DEFAULT_FRONT_HALF_WIDTH_DEG - 1.0))
	var just_outside := facing.rotated(deg_to_rad(LFDirectionalView.DEFAULT_FRONT_HALF_WIDTH_DEG + 1.0))

	assert_eq(LFDirectionalView.resolve(facing, just_inside), LFDirectionalView.View.FRONT)
	assert_ne(LFDirectionalView.resolve(facing, just_outside), LFDirectionalView.View.FRONT)
	assert_eq(autofree(LFDirectionalSprite3D.new()).front_half_width_deg, LFDirectionalView.DEFAULT_FRONT_HALF_WIDTH_DEG)
