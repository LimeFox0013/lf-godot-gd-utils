extends GutTest

var shaker: LFShaker


func before_each():
	shaker = add_child_autofree(LFShaker.new())


func test_shake_offsets_are_relative_to_the_original_transform_not_accumulated():
	# delta=0 holds time_counter and trauma_value fixed, so the noise-driven
	# offset is identical on both calls. If offsets accumulated onto the
	# previous frame's (already shaken) transform instead of re-basing on
	# original_transform each time, the second result would drift further.
	shaker.set_trauma(0.8)
	shaker._process(0.0)
	var after_first = shaker.transform
	shaker._process(0.0)
	var after_second = shaker.transform

	assert_eq(after_second, after_first)


func test_returns_to_the_original_transform_once_trauma_decays_to_zero_with_auto_reset():
	shaker.auto_reset_on_idle = true
	var original = shaker.transform
	shaker.shake(1.0)
	shaker._process(0.05)
	assert_ne(shaker.transform, original, "precondition: the node is shaken")

	shaker._process(1.0) # trauma decays to zero this frame

	assert_eq(shaker.trauma_value, 0.0)
	assert_eq(shaker.transform, original)


func test_idle_reset_happens_once_so_a_later_move_of_the_idle_node_is_kept():
	var original = shaker.transform
	shaker.shake(1.0)
	shaker._process(0.05)
	shaker._process(1.0) # decays to idle: reset to the original once
	assert_eq(shaker.transform, original)

	var moved = original.translated(Vector3(5, 5, 5))
	shaker.transform = moved
	shaker._process(0.016)
	shaker._process(0.016)

	assert_eq(shaker.transform, moved, "an idle shaker must not overwrite the transform every frame")


func test_a_shaker_that_never_shook_never_writes_the_transform():
	var moved = shaker.transform.translated(Vector3(5, 5, 5))
	shaker.transform = moved

	shaker._process(0.016)

	assert_eq(shaker.transform, moved)


func test_duration_mode_reset_also_happens_once():
	shaker.use_trauma_model = false
	var original = shaker.transform
	shaker.shake(0.5, 0.1)
	shaker._process(0.05)
	shaker._process(0.1) # duration runs out: reset once
	assert_eq(shaker.transform, original)

	var moved = original.translated(Vector3(0, 2, 0))
	shaker.transform = moved
	shaker._process(0.016)

	assert_eq(shaker.transform, moved)


func test_profile_defaults_match_the_nodes_defaults():
	var profile := LFShaker.Profile.new()
	assert_eq(profile.trauma_exponent, shaker.trauma_exponent)
	assert_eq(profile.trauma_decay_rate, shaker.trauma_decay_rate)
	assert_eq(profile.translation_frequency, shaker.translation_frequency)
	assert_eq(profile.rotation_frequency, shaker.rotation_frequency)
	assert_eq(profile.noise_roughness, shaker.noise_roughness)


func test_does_not_reset_when_auto_reset_on_idle_is_disabled():
	shaker.auto_reset_on_idle = false
	var original = shaker.transform
	shaker.shake(1.0)
	shaker._process(0.05)
	var last_shaken = shaker.transform
	assert_ne(last_shaken, original, "precondition: the node is shaken")

	shaker._process(1.0) # trauma decays to zero this frame

	assert_eq(shaker.transform, last_shaken, "without auto reset the last shaken frame stays")


func test_apply_shake_profile_adopts_every_field_of_the_profile():
	var profile = LFShaker.Profile.new(0.7, 0.3, 4.0, 3.0, 11.0, 13.0, 0.9)

	shaker.apply_shake_profile(profile)

	assert_eq(shaker.trauma_decay_rate, 4.0)
	assert_eq(shaker.trauma_exponent, 3.0)
	assert_eq(shaker.translation_frequency, 11.0)
	assert_eq(shaker.rotation_frequency, 13.0)
	assert_eq(shaker.noise_roughness, 0.9)
	assert_almost_eq(shaker.noise_gen.fractal_gain, lerpf(0.3, 0.6, 0.9), 0.0001, "the noise must be rebuilt for the new roughness")


func test_add_trauma_accumulates_and_clamps_to_the_zero_to_one_range():
	shaker.add_trauma(0.4)
	shaker.add_trauma(0.3)
	assert_almost_eq(shaker.trauma_value, 0.7, 0.0001, "trauma must add onto the current value")

	shaker.add_trauma(5.0)
	assert_eq(shaker.trauma_value, 1.0, "trauma must not exceed 1")

	shaker.add_trauma(-5.0)
	assert_eq(shaker.trauma_value, 0.0, "trauma must not drop below 0")


func test_shake_in_the_trauma_model_adds_its_clamped_magnitude_as_trauma():
	shaker.use_trauma_model = true
	shaker.shake(0.3)
	shaker.shake(0.3)
	assert_almost_eq(shaker.trauma_value, 0.6, 0.0001, "each shake must add its magnitude as trauma")

	shaker.shake(2.0)
	assert_eq(shaker.trauma_value, 1.0, "the magnitude is clamped and trauma capped at 1")


func test_trauma_decays_by_the_decay_rate_each_frame():
	shaker.trauma_decay_rate = 2.0
	shaker.set_trauma(1.0)

	shaker._process(0.1)

	assert_almost_eq(shaker.trauma_value, 0.8, 0.0001, "trauma must lose trauma_decay_rate per second")


func test_a_trauma_shake_moves_the_node_away_from_its_original_transform():
	var original = shaker.transform
	shaker.shake(1.0)

	shaker._process(0.05)

	assert_ne(shaker.transform, original, "a shake must offset the transform while trauma is high")


func test_duration_mode_holds_a_constant_trauma_for_the_duration_then_resets():
	shaker.use_trauma_model = false
	var original = shaker.transform

	shaker.shake(0.5, 0.2)
	assert_eq(shaker.trauma_value, 0.5, "duration mode sets trauma to the magnitude")

	shaker._process(0.1)
	assert_eq(shaker.trauma_value, 0.5, "trauma must not decay in duration mode")
	assert_ne(shaker.transform, original, "the node must shake while time is left")

	shaker._process(0.15)
	assert_eq(shaker.trauma_value, 0.0, "trauma must be zeroed once the duration runs out")
	assert_eq(shaker.transform, original, "the node must return to its original transform after the duration")


func test_duration_mode_overlapping_shakes_do_not_add_up():
	shaker.use_trauma_model = false
	shaker.shake(0.5, 1.0)
	shaker.shake(0.3, 1.0)
	assert_eq(shaker.trauma_value, 0.5, "the strongest running shake sets the trauma")


func test_duration_mode_a_weaker_shorter_shake_never_cuts_a_stronger_longer_one_short():
	shaker.use_trauma_model = false
	shaker.shake(1.0, 2.0)
	shaker._process(0.1)
	shaker.shake(0.1, 0.1)
	shaker._process(0.15)

	assert_eq(shaker.trauma_value, 1.0, "the strong shake keeps running at full strength")
	assert_almost_eq(shaker.time_left, 1.75, 0.0001, "and keeps its own remaining time")


func test_duration_mode_a_stronger_shorter_shake_ends_on_time_and_the_longer_one_carries_on():
	shaker.use_trauma_model = false
	shaker.shake(0.2, 1.0)
	shaker.shake(0.9, 0.1)
	shaker._process(0.05)
	assert_almost_eq(shaker.trauma_value, 0.9, 0.0001, "the strong shake leads while it runs")

	shaker._process(0.1)
	assert_almost_eq(shaker.trauma_value, 0.2, 0.0001, "then the weaker, longer one carries on")
	assert_almost_eq(shaker.time_left, 0.85, 0.0001)


func test_stop_shake_zeroes_trauma_and_restores_the_original_transform():
	var original = shaker.transform
	shaker.use_trauma_model = false
	shaker.shake(1.0, 5.0)
	shaker._process(0.05)

	shaker.stop_shake()

	assert_eq(shaker.trauma_value, 0.0, "stop_shake must zero trauma")
	assert_eq(shaker.time_left, 0.0, "stop_shake must zero the remaining duration")
	assert_eq(shaker.transform, original, "stop_shake must restore the original transform by default")


func test_stop_shake_without_reset_leaves_the_transform_where_it_is():
	shaker.shake(1.0)
	shaker._process(0.05)
	var shaken = shaker.transform

	shaker.stop_shake(false)

	assert_eq(shaker.trauma_value, 0.0, "stop_shake must zero trauma")
	assert_eq(shaker.transform, shaken, "stop_shake(false) must not touch the transform")


func test_recapture_original_transform_re_bases_a_running_shake():
	shaker.shake(1.0)
	shaker._process(0.05)
	var moved = Transform3D(Basis(), Vector3(3, 0, 0))
	shaker.transform = moved

	shaker.recapture_original_transform()
	shaker._process(0.05)
	assert_lt(shaker.transform.origin.distance_to(moved.origin), 0.5, "the shake now runs around the recaptured transform")
	shaker._process(1.0) # decays to idle

	assert_eq(shaker.transform, moved, "the idle reset returns to the recaptured transform")


func test_moving_the_node_between_shakes_moves_the_rest_pose():
	shaker.shake(1.0)
	shaker._process(0.05)
	shaker._process(1.0) # idle
	var moved = Transform3D(Basis.from_euler(Vector3(0.3, 0, 0)), Vector3(5, 0, 0))
	shaker.transform = moved

	shaker.shake(1.0)
	shaker._process(0.016)
	assert_lt(shaker.transform.origin.distance_to(moved.origin), 0.5, "the next shake runs around where the node now is")
	shaker._process(1.0)

	assert_eq(shaker.transform, moved, "and returns there, not to the pose from before the move")


func test_rotation_is_about_the_nodes_own_axes():
	var pitched := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-45.0), 0, 0)), Vector3.ZERO)
	shaker.transform = pitched
	shaker.enable_translation = false
	shaker.rotation_strength_deg = Vector3(0, 0, 10) # roll only
	shaker.set_trauma(1.0)
	shaker.trauma_decay_rate = 0.1
	var forward := -pitched.basis.z
	var largest_angle := 0.0
	var largest_roll := 0.0
	for i in 60:
		shaker._process(1.0 / 60.0)
		largest_angle = maxf(largest_angle, forward.angle_to(-shaker.transform.basis.z))
		largest_roll = maxf(largest_roll, pitched.basis.x.angle_to(shaker.transform.basis.x))

	assert_gt(largest_roll, deg_to_rad(0.5), "precondition: the node rolls")
	assert_lt(largest_angle, 0.0001, "a roll-only shake never changes where the node looks")


func test_the_default_noise_moves_smoothly_at_60_and_at_144_fps():
	for fps in [60.0, 144.0]:
		var s: LFShaker = add_child_autofree(LFShaker.new())
		s.set_trauma(1.0)
		s.trauma_decay_rate = 0.1
		var xs: Array[float] = []
		for i in 120:
			s._process(1.0 / fps)
			xs.append(s.transform.origin.x)
		assert_gt(_lag1_autocorrelation(xs), 0.6, "consecutive frames at %d fps follow one smooth motion, not jitter" % fps)


func test_the_offset_at_a_given_time_does_not_depend_on_the_frame_rate():
	var a: LFShaker = add_child_autofree(LFShaker.new())
	var b: LFShaker = add_child_autofree(LFShaker.new())
	a.shake(1.0)
	b.shake(1.0)
	for i in 15:
		a._process(1.0 / 60.0)
	for i in 36:
		b._process(1.0 / 144.0)

	assert_almost_eq(a.trauma_value, b.trauma_value, 0.0001)
	assert_true(a.transform.is_equal_approx(b.transform), "the same elapsed time gives the same offset")


func test_turning_enabled_off_mid_shake_returns_the_node_to_rest():
	var original = shaker.transform
	shaker.shake(1.0)
	shaker._process(0.05)
	assert_ne(shaker.transform, original, "precondition: the node is shaken")

	shaker.enabled = false

	assert_eq(shaker.transform, original)
	assert_eq(shaker.trauma_value, 0.0)


func test_a_disabled_shaker_ignores_shakes():
	shaker.enabled = false
	shaker.shake(1.0)
	shaker.add_trauma(0.5)
	shaker.enabled = true
	var original = shaker.transform

	shaker._process(0.05)

	assert_eq(shaker.trauma_value, 0.0)
	assert_eq(shaker.transform, original)


func test_translation_and_rotation_can_each_be_switched_off():
	var original = shaker.transform
	shaker.enable_rotation = false
	shaker.shake(1.0)
	shaker._process(0.05)
	assert_ne(shaker.transform.origin, original.origin)
	assert_eq(shaker.transform.basis, original.basis, "no rotation while it is off")

	shaker.stop_shake()
	shaker.enable_rotation = true
	shaker.enable_translation = false
	shaker.shake(1.0)
	shaker._process(0.05)
	assert_eq(shaker.transform.origin, original.origin, "no translation while it is off")
	assert_ne(shaker.transform.basis, original.basis)


func test_the_offset_scales_with_the_strength():
	shaker.enable_rotation = false
	shaker.set_trauma(1.0)
	var weak := shaker.compute_translation(1.0)
	shaker.translation_strength *= 2.0
	var strong := shaker.compute_translation(1.0)

	assert_true(strong.is_equal_approx(weak * 2.0))


func test_noise_is_ready_before_the_node_enters_the_tree():
	var loose := LFShaker.new()
	loose.time_counter = 0.3

	assert_ne(loose.compute_translation(1.0), Vector3.ZERO, "computing an offset never needs _ready")
	loose.free()


func test_changing_the_seed_rebuilds_the_noise():
	shaker.time_counter = 0.37
	var before := shaker.compute_translation(1.0)

	shaker.seed_value = 777

	assert_eq(shaker.noise_gen.seed, 777)
	assert_ne(shaker.compute_translation(1.0), before)


func test_going_idle_below_the_threshold_zeroes_the_trauma():
	shaker.idle_trauma_threshold = 0.01
	shaker.set_trauma(0.05) # intensity 0.0025, below the threshold

	shaker._process(0.001)

	assert_eq(shaker.trauma_value, 0.0, "an idle shaker holds no trauma")


func test_trauma_exponent_turns_trauma_into_intensity():
	shaker.enable_rotation = false
	shaker.trauma_decay_rate = 0.1
	shaker.time_counter = 0.4
	var full := shaker.compute_translation(1.0)

	shaker.trauma_exponent = 1.0
	shaker.set_trauma(0.5)
	shaker._process(0.0)
	var linear := shaker.transform.origin
	shaker.stop_shake()

	shaker.trauma_exponent = 2.0
	shaker.set_trauma(0.5)
	shaker._process(0.0)
	var squared := shaker.transform.origin

	assert_true(linear.is_equal_approx(full * 0.5), "intensity = trauma ^ 1")
	assert_true(squared.is_equal_approx(full * 0.25), "intensity = trauma ^ 2")


func test_set_trauma_clamps_to_the_zero_to_one_range():
	shaker.set_trauma(3.0)
	assert_eq(shaker.trauma_value, 1.0)
	shaker.set_trauma(-1.0)
	assert_eq(shaker.trauma_value, 0.0)


func test_a_fixed_duration_shake_with_no_magnitude_or_no_duration_is_ignored():
	shaker.use_trauma_model = false
	var rest := shaker.transform

	shaker.shake(0.0, 1.0)
	shaker.shake(0.8, 0.0)
	shaker.shake(-0.5, 1.0)
	shaker._process(0.05)

	assert_eq(shaker.trauma_value, 0.0)
	assert_eq(shaker.time_left, 0.0)
	assert_eq(shaker.transform, rest, "nothing moved")


func test_an_intensity_under_the_idle_threshold_never_moves_the_node():
	shaker.idle_trauma_threshold = 0.05
	var rest := shaker.transform
	shaker.set_trauma(0.2) # intensity 0.04
	shaker._process(0.0)
	assert_eq(shaker.transform, rest)

	shaker.set_trauma(0.3) # intensity 0.09, above it
	shaker._process(0.0)
	assert_ne(shaker.transform, rest)


func test_add_trauma_at_falls_off_with_distance_from_the_focus():
	var focus := Vector3(10, 0, 10)
	shaker.add_trauma_at(focus, focus, 0.4, 20.0)
	assert_almost_eq(shaker.trauma_value, 0.4, 0.0001, "in full at the focus")
	shaker.stop_shake()

	shaker.add_trauma_at(focus + Vector3(15, 0, 0), focus, 0.4, 20.0)
	assert_almost_eq(shaker.trauma_value, 0.1, 0.0001, "a quarter of the way in")
	shaker.stop_shake()

	shaker.add_trauma_at(focus + Vector3(0, 0, 20), focus, 0.4, 20.0)
	assert_eq(shaker.trauma_value, 0.0, "nothing at the range")


func test_add_trauma_at_is_planar_by_default_and_3d_on_request():
	shaker.add_trauma_at(Vector3(0, 50, 0), Vector3.ZERO, 0.4, 20.0)
	assert_almost_eq(shaker.trauma_value, 0.4, 0.0001, "height ignored")
	shaker.stop_shake()

	shaker.add_trauma_at(Vector3(0, 10, 0), Vector3.ZERO, 0.4, 20.0, false)
	assert_almost_eq(shaker.trauma_value, 0.2, 0.0001, "height counted")


func test_add_trauma_at_ignores_a_zero_range_and_a_disabled_shaker():
	shaker.add_trauma_at(Vector3.ZERO, Vector3.ZERO, 0.4, 0.0)
	assert_eq(shaker.trauma_value, 0.0)
	shaker.enabled = false
	shaker.add_trauma_at(Vector3.ZERO, Vector3.ZERO, 0.4, 10.0)
	assert_eq(shaker.trauma_value, 0.0)


func _lag1_autocorrelation(xs: Array[float]) -> float:
	var mean := 0.0
	for x in xs:
		mean += x
	mean /= xs.size()
	var num := 0.0
	var den := 0.0
	for i in xs.size() - 1:
		num += (xs[i] - mean) * (xs[i + 1] - mean)
	for x in xs:
		den += (x - mean) * (x - mean)
	return num / den


func test_trauma_is_cleared_under_the_fixed_duration_model():
	shaker.use_trauma_model = false
	var rest := shaker.transform
	shaker.add_trauma(0.8)
	shaker._process(0.05)
	assert_eq(shaker.trauma_value, 0.0, "only timed shakes drive the fixed-duration model")
	assert_eq(shaker.transform, rest)


func test_compute_rotation_scales_with_the_strength_in_radians():
	shaker.time_counter = 0.4
	var weak := shaker.compute_rotation(1.0)
	assert_ne(weak, Vector3.ZERO)
	assert_lt(absf(weak.x), deg_to_rad(shaker.rotation_strength_deg.x) + 0.0001)
	shaker.rotation_strength_deg *= 2.0
	assert_true(shaker.compute_rotation(1.0).is_equal_approx(weak * 2.0))
	assert_true(shaker.compute_rotation(0.5).is_equal_approx(weak))


func test_setup_noise_builds_the_noise_from_the_seed_and_roughness():
	shaker.seed_value = 42
	shaker.noise_roughness = 0.0
	shaker.setup_noise()
	assert_eq(shaker.noise_gen.seed, 42)
	assert_eq(shaker.noise_gen.frequency, 1.0, "the speed comes from the frequency exports alone")
	assert_eq(shaker.noise_gen.fractal_octaves, 1, "smooth: one octave")
	shaker.noise_roughness = 1.0
	shaker.setup_noise()
	assert_eq(shaker.noise_gen.fractal_octaves, 3, "rough: three octaves")
	assert_almost_eq(shaker.noise_gen.fractal_gain, 0.6, 0.0001)


func test_time_counter_advances_only_while_enabled():
	shaker._process(0.25)
	assert_almost_eq(shaker.time_counter, 0.25, 0.0001)
	shaker.enabled = false
	shaker._process(0.25)
	assert_almost_eq(shaker.time_counter, 0.25, 0.0001, "a disabled shaker's clock stands still")


func test_a_higher_frequency_runs_through_the_noise_faster():
	shaker.time_counter = 0.4
	shaker.translation_frequency = 4.0
	shaker.rotation_frequency = 4.0
	var slow_translation := shaker.compute_translation(1.0)
	var slow_rotation := shaker.compute_rotation(1.0)
	shaker.time_counter = 0.2
	shaker.translation_frequency = 8.0
	shaker.rotation_frequency = 8.0
	assert_true(shaker.compute_translation(1.0).is_equal_approx(slow_translation), "double speed at half the time is the same point")
	assert_true(shaker.compute_rotation(1.0).is_equal_approx(slow_rotation))


func test_a_profile_stores_its_arguments_in_order():
	var profile := LFShaker.Profile.new(0.7, 0.3, 4.0, 3.0, 11.0, 13.0, 0.9)
	assert_eq(profile.magnitude, 0.7)
	assert_eq(profile.duration, 0.3)
	assert_eq(profile.trauma_decay_rate, 4.0)
	assert_eq(profile.trauma_exponent, 3.0)
	assert_eq(profile.translation_frequency, 11.0)
	assert_eq(profile.rotation_frequency, 13.0)
	assert_eq(profile.noise_roughness, 0.9)


func test_a_nan_shake_or_trauma_is_ignored_and_never_corrupts_the_transform():
	var rest := shaker.transform
	shaker.add_trauma(NAN)
	shaker.set_trauma(NAN)
	shaker.shake(NAN)
	assert_eq(shaker.trauma_value, 0.0)
	shaker.use_trauma_model = false
	shaker.shake(NAN, 1.0)
	shaker.shake(0.5, NAN)
	shaker._process(0.016)
	assert_eq(shaker.trauma_value, 0.0)
	assert_eq(shaker.transform, rest)


func test_the_offset_never_exceeds_the_strength():
	shaker.translation_strength = Vector3(1, 2, 3)
	var largest := Vector3.ZERO
	for i in 2000:
		shaker.time_counter = i * 0.013
		largest = largest.max(shaker.compute_translation(1.0).abs())
	assert_true(largest.x <= 1.0 and largest.y <= 2.0 and largest.z <= 3.0, "largest offset %s" % largest)
	assert_gt(largest.x, 0.5, "precondition: the noise swings well out")


func test_entering_the_tree_takes_the_placed_transform_as_the_rest_pose():
	var placed := LFShaker.new()
	placed.transform = Transform3D(Basis.from_euler(Vector3(0, 0.5, 0)), Vector3(1, 2, 3))
	add_child_autofree(placed)

	assert_eq(placed.original_transform, placed.transform)


func test_the_shake_runs_by_itself_on_real_frames():
	var rest := shaker.transform
	shaker.trauma_decay_rate = 0.1
	shaker.shake(1.0)

	await wait_process_frames(3)

	assert_gt(shaker.time_counter, 0.0, "the shaker advances in its own _process")
	assert_ne(shaker.transform, rest)


func test_a_shake_added_mid_shake_keeps_the_rest_pose():
	var rest := shaker.transform
	shaker.shake(0.6)
	shaker._process(0.05)
	shaker.shake(0.6) # the node is shaken now; this must not become the new rest
	shaker._process(0.05)
	shaker._process(1.0)

	assert_eq(shaker.transform, rest)


func test_a_timed_shake_added_mid_shake_keeps_the_rest_pose():
	shaker.use_trauma_model = false
	var rest := shaker.transform
	shaker.shake(0.8, 0.2)
	shaker._process(0.05)
	shaker.shake(0.8, 0.2)
	shaker._process(0.05)
	shaker._process(1.0)

	assert_eq(shaker.transform, rest)


func test_without_auto_reset_the_next_shake_starts_from_the_last_shaken_frame():
	shaker.auto_reset_on_idle = false
	shaker.shake(1.0)
	shaker._process(0.05)
	shaker._process(1.0) # idle; the last shaken frame stays
	var left := shaker.transform

	shaker.shake(1.0)
	shaker._process(0.05)
	shaker.stop_shake()

	assert_eq(shaker.original_transform, left)
	assert_eq(shaker.transform, left)


func test_stop_shake_on_an_idle_shaker_never_writes_the_transform():
	var moved := shaker.transform.translated(Vector3(4, 0, 0))
	shaker.transform = moved

	shaker.stop_shake()

	assert_eq(shaker.transform, moved)


func test_writing_enabled_true_on_an_enabled_shaker_keeps_the_shake_running():
	shaker.shake(0.8)
	shaker._process(0.01)

	shaker.enabled = true

	assert_gt(shaker.trauma_value, 0.0)


func test_a_profile_under_the_fixed_duration_model_runs_for_its_duration():
	shaker.use_trauma_model = false
	shaker.apply_shake_profile(LFShaker.Profile.new(0.7, 0.3))

	assert_almost_eq(shaker.trauma_value, 0.7, 0.0001)
	assert_almost_eq(shaker.time_left, 0.3, 0.0001)


func test_a_profile_applied_while_disabled_keeps_its_settings_but_does_not_shake():
	shaker.enabled = false

	shaker.apply_shake_profile(LFShaker.Profile.new(0.7, 0.3, 4.0, 3.0, 11.0, 13.0, 0.9))

	assert_eq(shaker.trauma_value, 0.0)
	assert_eq(shaker.trauma_decay_rate, 4.0)
	assert_eq(shaker.noise_roughness, 0.9)


func test_an_infinite_trauma_clamps_to_the_range():
	shaker.add_trauma(INF)
	assert_eq(shaker.trauma_value, 1.0)
	shaker.add_trauma(-INF)
	assert_eq(shaker.trauma_value, 0.0)
	shaker.set_trauma(INF)
	assert_eq(shaker.trauma_value, 1.0)


func test_add_trauma_at_ignores_a_nan_trauma_and_a_zero_trauma_leaves_the_rest_pose_alone():
	shaker.add_trauma_at(Vector3.ZERO, Vector3.ZERO, NAN, 10.0)
	assert_eq(shaker.trauma_value, 0.0)
	var moved := shaker.transform.translated(Vector3(0, 3, 0))
	shaker.transform = moved
	shaker.add_trauma_at(Vector3.ZERO, Vector3.ZERO, 0.0, 10.0)
	assert_eq(shaker.trauma_value, 0.0)
	assert_ne(shaker.original_transform, moved, "a zero jolt captures nothing")


func test_a_negative_trauma_at_the_focus_calms_a_running_shake():
	shaker.set_trauma(0.8)
	shaker.add_trauma_at(Vector3.ZERO, Vector3.ZERO, -0.3, 10.0)
	assert_almost_eq(shaker.trauma_value, 0.5, 0.0001)
