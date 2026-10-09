extends GutTest

var view: LFDirectionalSprite3D
var sprite: AnimatedSprite3D


func before_each():
	view = LFDirectionalSprite3D.new()
	sprite = AnimatedSprite3D.new()
	view.sprite = sprite
	add_child_autofree(view)
	view.add_child(sprite)


func _frames(names: Array, fps := 10.0, frame_count := 1) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for animation in names:
		frames.add_animation(animation)
		frames.set_animation_speed(animation, fps)
		for i in frame_count:
			frames.add_frame(animation, blank)
	return frames


func test_does_nothing_without_a_sprite():
	view.sprite = null
	view.update_view(Vector3.ZERO, Vector3(0, 0, 1))
	view.set_dying(true)
	assert_eq(view.dying_duration(), 0.0)
	assert_null(view.sprite)
	assert_engine_error_count(0)


func test_does_nothing_when_the_viewer_stands_on_the_character():
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3(5, 0, 5), Vector3(5, 0, 5))
	assert_eq(sprite.animation, &"default", 'the animation is not changed')
	assert_false(sprite.is_playing(), 'nothing is played')


func test_does_nothing_before_the_frames_exist():
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	view.set_dying(true)
	assert_false(sprite.flip_h, 'a mirrored side with no art leaves the sprite alone')
	assert_false(sprite.is_playing())


func test_a_missing_animation_leaves_the_flip_of_the_one_playing():
	sprite.sprite_frames = _frames(["side_walk"])
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(1, 0, 0))
	view.state = &"run"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	assert_eq(sprite.animation, &"side_walk")
	assert_false(sprite.flip_h, 'side_walk keeps the flip it plays with')


func test_frames_assigned_later_are_picked_up_on_the_next_update():
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_eq(sprite.animation, &"front_idle")
	assert_true(sprite.is_playing())


func test_a_freed_sprite_counts_as_none():
	sprite.free()
	view.update_view(Vector3.ZERO, Vector3(0, 0, 1))
	view.set_dying(true)
	assert_eq(view.dying_duration(), 0.0)
	assert_engine_error_count(0)


func test_plays_front_idle_when_the_character_faces_the_viewer():
	sprite.sprite_frames = _frames(["front_idle"])
	view.facing_xz = Vector2.UP
	view.state = &"idle"
	# Vector2.UP is (0, -1), facing -Z: the viewer stands at -Z to be looked at.
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_eq(sprite.animation, &"front_idle")
	assert_false(sprite.flip_h)


func test_mirrors_side_l_onto_the_shared_side_animation():
	sprite.sprite_frames = _frames(["side_walk"])
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	assert_eq(sprite.animation, &"side_walk")
	assert_true(sprite.flip_h)


func test_side_r_plays_the_same_animation_unflipped():
	sprite.sprite_frames = _frames(["side_walk"])
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(1, 0, 0))
	assert_eq(sprite.animation, &"side_walk")
	assert_false(sprite.flip_h)


func test_authored_sides_play_their_own_animation_unflipped():
	sprite.sprite_frames = _frames(["side_l_walk", "side_r_walk"])
	view.mirror_sides = false
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	assert_eq(sprite.animation, &"side_l_walk")
	assert_false(sprite.flip_h)


func test_skips_a_missing_animation():
	sprite.sprite_frames = _frames(["back_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_eq(sprite.animation, &"default", 'front_idle is missing; nothing else is played')
	assert_false(sprite.is_playing())


func test_a_state_change_plays_the_new_animation():
	sprite.sprite_frames = _frames(["front_idle", "front_action_a"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.state = &"action_a"
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_eq(sprite.animation, &"front_action_a")


func test_dying_plays_the_death_animation_of_the_current_view_mirrored():
	sprite.sprite_frames = _frames(["side_walk", "side_die"])
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	view.set_dying(true)
	assert_true(view.dying)
	assert_eq(sprite.animation, &"side_die")
	assert_true(sprite.flip_h, "the left side stays flipped")
	assert_true(sprite.is_playing())


func test_dying_with_authored_sides_plays_that_sides_death_unflipped():
	sprite.sprite_frames = _frames(["side_l_walk", "side_l_die"])
	view.mirror_sides = false
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	view.set_dying(true)
	assert_eq(sprite.animation, &"side_l_die")
	assert_false(sprite.flip_h)


func test_a_dying_character_keeps_the_view_it_died_in():
	sprite.sprite_frames = _frames(["front_idle", "front_die", "back_die"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	view.update_view(Vector3.ZERO, Vector3(0, 0, 1))
	assert_eq(sprite.animation, &"front_die")


func test_leaving_dying_returns_to_the_state_loop():
	sprite.sprite_frames = _frames(["front_idle", "front_die"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	view.set_dying(false)
	assert_false(view.dying)
	assert_eq(sprite.animation, &"front_idle")


func test_a_custom_die_segment_names_the_death_animation():
	sprite.sprite_frames = _frames(["front_idle", "front_segment_a"])
	view.die_segment = &"segment_a"
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	assert_eq(sprite.animation, &"front_segment_a")


func test_dying_duration_is_frames_over_fps_and_zero_without_the_animation():
	sprite.sprite_frames = _frames(["front_idle"])
	assert_eq(view.dying_duration(), 0.0)
	sprite.sprite_frames = _frames(["front_die"], 8.0, 4)
	assert_almost_eq(view.dying_duration(), 0.5, 0.0001)


func test_leaving_dying_without_death_art_plays_the_state_loop_again():
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	view.set_dying(false)
	assert_eq(sprite.animation, &"front_idle")
	assert_true(sprite.is_playing(), "a revived character is not left frozen")


func test_dying_is_read_only():
	view.dying = true
	assert_false(view.dying)


func test_a_wider_front_wedge_reaches_the_sprite():
	sprite.sprite_frames = _frames(["front_idle", "side_idle"])
	var at_60 := Vector2.UP.rotated(deg_to_rad(60.0))
	view.update_view(Vector3.ZERO, Vector3(at_60.x, 0, at_60.y))
	assert_eq(sprite.animation, &"side_idle")
	view.front_half_width_deg = 70.0
	view.update_view(Vector3.ZERO, Vector3(at_60.x, 0, at_60.y))
	assert_eq(sprite.animation, &"front_idle")


func test_dying_duration_follows_frame_durations_and_the_speed_scale():
	var frames := _frames(["front_die"], 8.0, 4)
	frames.set_frame(&"front_die", 0, frames.get_frame_texture(&"front_die", 0), 3.0)
	sprite.sprite_frames = frames
	assert_almost_eq(view.dying_duration(), 6.0 / 8.0, 0.0001, 'one frame held three times as long')
	sprite.speed_scale = 2.0
	assert_almost_eq(view.dying_duration(), 6.0 / 16.0, 0.0001, 'twice as fast')
	sprite.speed_scale = 0.0
	assert_eq(view.dying_duration(), 0.0, 'a paused sprite never finishes')


func test_an_animation_added_later_to_the_same_frames_is_played_on_the_next_update():
	var frames := _frames(["front_idle"])
	sprite.sprite_frames = frames
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_eq(sprite.animation, &"front_idle", 'no front_walk yet: the sprite is left alone')

	frames.add_animation(&"front_walk")
	frames.add_frame(&"front_walk", frames.get_frame_texture(&"front_idle", 0))
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))

	assert_eq(sprite.animation, &"front_walk", 'same view, state and frames, but now the animation exists')


func test_a_new_view_has_the_documented_defaults():
	var fresh := LFDirectionalSprite3D.new()
	assert_null(fresh.sprite)
	assert_true(fresh.mirror_sides)
	assert_eq(fresh.front_half_width_deg, 45.0)
	assert_eq(fresh.die_segment, &"die")
	assert_eq(fresh.state, &"idle")
	assert_eq(fresh.facing_xz, Vector2.UP)
	assert_false(fresh.dying)
	fresh.free()


func test_the_facing_turns_the_view():
	sprite.sprite_frames = _frames(["front_idle", "back_idle"])
	view.facing_xz = Vector2.RIGHT
	view.update_view(Vector3(2, 0, 2), Vector3(5, 3, 2))
	assert_eq(sprite.animation, &"front_idle", 'facing +X, a viewer at +X sees the front')
	view.update_view(Vector3(2, 0, 2), Vector3(-5, 3, 2))
	assert_eq(sprite.animation, &"back_idle")


func test_an_unchanged_view_state_and_frames_leave_the_sprite_alone():
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	sprite.flip_h = true
	sprite.stop()
	view.update_view(Vector3.ZERO, Vector3(0, 0, -2))
	assert_true(sprite.flip_h, 'not touched')
	assert_false(sprite.is_playing(), 'not restarted')


func test_new_frames_are_applied_though_view_and_state_are_unchanged():
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	sprite.flip_h = true
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	assert_false(sprite.flip_h, 'the new frames were applied')


func test_dying_again_restarts_a_finished_death_from_its_first_frame():
	sprite.sprite_frames = _frames(["front_idle", "front_die"], 10.0, 3)
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	sprite.frame = 2
	sprite.stop()
	sprite.frame = 2
	view.set_dying(false)
	view.set_dying(true)
	assert_eq(sprite.animation, &"front_die")
	assert_eq(sprite.frame, 0)
	assert_true(sprite.is_playing())


func test_dying_without_death_art_stops_the_sprite():
	sprite.sprite_frames = _frames(["front_idle"])
	view.update_view(Vector3.ZERO, Vector3(0, 0, -1))
	view.set_dying(true)
	assert_true(view.dying)
	assert_false(sprite.is_playing())
	assert_eq(sprite.animation, &"front_idle")


func test_dying_duration_is_for_the_view_last_resolved():
	var frames := _frames(["side_walk"])
	frames.add_animation(&"side_die")
	frames.set_animation_speed(&"side_die", 4.0)
	for i in 2:
		frames.add_frame(&"side_die", frames.get_frame_texture(&"side_walk", 0))
	sprite.sprite_frames = frames
	view.state = &"walk"
	view.update_view(Vector3.ZERO, Vector3(-1, 0, 0))
	assert_almost_eq(view.dying_duration(), 0.5, 0.0001)


func test_dying_duration_is_zero_for_a_death_animation_without_fps():
	sprite.sprite_frames = _frames(["front_die"], 0.0, 3)
	assert_eq(view.dying_duration(), 0.0)
