extends GutTest

## `LFInterpolationBuffer` and `LFPlaybackClock` together, fed the way a networked client
## feeds them: for each update, every named entity's sample (with the clock's newest stamp
## as `previous_time`), then the update's stamp; each frame, advance the clock and sample.

var clock: LFPlaybackClock
var buffers: Dictionary


func before_each():
	clock = LFPlaybackClock.new()
	buffers = {}


func _update(time: float, values: Dictionary) -> void:
	for id in values:
		if not buffers.has(id):
			buffers[id] = LFInterpolationBuffer.new()
		buffers[id].add_sample(time, values[id], clock.latest)
	clock.stamp(time)


func _x(id: String) -> float:
	return buffers[id].sample_at(clock.time).x


## Late and bunched updates never show as a stop and a start.
func test_playback_keeps_moving_through_late_and_bunched_updates():
	clock.delay = 0.2
	_update(1.0, {'item_a': Vector3.ZERO})
	_update(1.1, {'item_a': Vector3(1, 0, 0)})

	var xs: Array[float] = []
	for frame in 20:
		if frame == 6: # two updates late, arriving in one frame
			_update(1.2, {'item_a': Vector3(2, 0, 0)})
			_update(1.3, {'item_a': Vector3(3, 0, 0)})
		clock.advance(0.03)
		xs.append(_x('item_a'))

	var started := xs.find(xs.filter(func(x): return x > 0.0)[0])
	var arrived := xs.find(3.0)
	assert_gt(arrived, started, 'it reaches the newest position')
	for i in range(started + 1, arrived + 1):
		assert_gt(xs[i], xs[i - 1], 'frame %d: still moving, never standing' % i)


func test_playback_trails_the_newest_stamp_by_the_delay():
	clock.delay = 0.1
	_update(1.0, {'item_a': Vector3.ZERO})
	_update(1.1, {'item_a': Vector3(1, 0, 0)})
	_update(1.2, {'item_a': Vector3(2, 0, 0)})
	clock.time = 1.05

	clock.advance(0.0)

	assert_almost_eq(_x('item_a'), 0.5, 0.001, 'halfway between the samples at 1.0 and 1.1')


## An update leaves out an entity that stood still; its next move starts from when it last
## stood, not from the last time it was named.
func test_a_value_left_out_of_updates_stood_still_until_its_next_change():
	clock.delay = 0.05
	_update(1.0, {'still': Vector3.ZERO, 'moving': Vector3.ZERO})
	for time in [1.1, 1.2, 1.3]:
		_update(time, {'moving': Vector3(time, 0, 0)})
	_update(1.4, {'still': Vector3(1, 0, 0)})
	clock.time = 1.35

	clock.advance(0.0)

	assert_almost_eq(_x('still'), 0.5, 0.001, 'halfway through its one move from 1.3 to 1.4')


func test_the_first_stamp_starts_playback_delay_behind_it():
	clock.delay = 0.2
	assert_false(clock.is_started())
	assert_eq(clock.advance(0.1), -INF, 'nothing to play before a stamp')

	clock.stamp(5.0)

	assert_true(clock.is_started())
	assert_almost_eq(clock.time, 4.8, 0.0001)


func test_it_never_plays_past_the_newest_stamp():
	clock.delay = 0.1
	clock.stamp(1.0)

	assert_almost_eq(clock.advance(0.5), 1.0, 0.0001)


func test_a_small_drift_closes_slowly_and_a_big_one_jumps():
	clock = LFPlaybackClock.new(0.1, 0.5, 0.5)
	clock.stamp(1.0)
	clock.stamp(1.3) # wanted is now 1.2, playback at 0.9: a 0.3 gap

	var time := clock.advance(0.0)
	assert_almost_eq(time, 0.9, 0.0001, 'no time passed, so no correction')
	time = clock.advance(0.1)
	assert_almost_eq(time, 1.0 + 0.2 * 0.05, 0.0001, 'real speed plus 5% of the remaining gap')

	clock.stamp(3.0)
	assert_almost_eq(clock.advance(0.0), 2.9, 0.0001, 'a gap over snap_seconds jumps')


func test_the_constructor_sets_the_tuning():
	var tuned := LFPlaybackClock.new(0.3, 0.2, 1.5)
	assert_eq([tuned.delay, tuned.correction_rate, tuned.snap_seconds], [0.3, 0.2, 1.5])
	assert_eq(tuned.time, -INF)
	assert_eq(tuned.latest, -INF)


func test_the_default_tuning():
	assert_eq([LFPlaybackClock.DEFAULT_DELAY, LFPlaybackClock.DEFAULT_CORRECTION_RATE, LFPlaybackClock.DEFAULT_SNAP_SECONDS], [0.1, 0.5, 0.5])
	var plain := LFPlaybackClock.new()
	assert_eq([plain.delay, plain.correction_rate, plain.snap_seconds], [0.1, 0.5, 0.5])


func test_an_older_stamp_changes_nothing_and_reset_forgets():
	clock.stamp(2.0)
	clock.stamp(1.0)
	assert_eq(clock.latest, 2.0)

	clock.reset()

	assert_false(clock.is_started())
	assert_eq(clock.latest, -INF)


func test_an_empty_buffer_samples_null():
	var buffer := LFInterpolationBuffer.new()
	assert_true(buffer.is_empty())
	assert_null(buffer.sample_at(1.0))


func test_it_holds_the_first_sample_before_it_and_the_last_after():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(1.0, 10.0)
	buffer.add_sample(2.0, 20.0)

	assert_eq(buffer.sample_at(0.0), 10.0)
	assert_eq(buffer.sample_at(1.5), 15.0)
	assert_eq(buffer.sample_at(3.0), 20.0)
	assert_eq(buffer.size(), 1, 'samples played past are dropped')


func test_an_older_or_equal_stamp_is_ignored():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(2.0, 1.0)
	buffer.add_sample(2.0, 5.0)
	buffer.add_sample(1.0, 5.0)

	assert_eq(buffer.size(), 1)
	assert_eq(buffer.latest_time(), 2.0)


func test_values_blend_by_type():
	var cases := [
		[Vector2.ZERO, Vector2(2, 4), Vector2(1, 2)],
		[Color.BLACK, Color.WHITE, Color(0.5, 0.5, 0.5)],
		[Transform3D(), Transform3D(Basis(), Vector3(2, 0, 0)), Transform3D(Basis(), Vector3(1, 0, 0))],
		['a', 'b', 'a'],
	]
	for c in cases:
		var buffer := LFInterpolationBuffer.new()
		buffer.add_sample(0.0, c[0])
		buffer.add_sample(1.0, c[1])
		assert_eq(buffer.sample_at(0.5), c[2], 'blending %s' % type_string(typeof(c[0])))
	var more := [
		[Vector3.ZERO, Vector3(2, 4, 6), Vector3(1, 2, 3)],
		[Vector4.ZERO, Vector4(2, 2, 2, 2), Vector4.ONE],
		[0, 3, 1.5],
		[Transform2D(0.0, Vector2.ZERO), Transform2D(0.0, Vector2(4, 0)), Transform2D(0.0, Vector2(2, 0))],
		[1.0, Vector2.ONE, 1.0],
	]
	for c in more:
		var buffer := LFInterpolationBuffer.new()
		buffer.add_sample(0.0, c[0])
		buffer.add_sample(1.0, c[1])
		assert_eq(buffer.sample_at(0.5), c[2], 'blending %s' % type_string(typeof(c[0])))
	var basis := LFInterpolationBuffer.new()
	basis.add_sample(0.0, Basis.IDENTITY)
	basis.add_sample(1.0, Basis(Vector3.UP, PI / 2))
	assert_almost_eq(basis.sample_at(0.5).get_rotation_quaternion().get_angle(), PI / 4, 0.0001)
	var turn := LFInterpolationBuffer.new()
	turn.add_sample(0.0, Quaternion.IDENTITY)
	turn.add_sample(1.0, Quaternion(Vector3.UP, PI / 2))
	assert_almost_eq(turn.sample_at(0.5).get_angle(), PI / 4, 0.0001)


## A unit grows while it turns: its basis carries scale as well as rotation.
func test_a_scaled_basis_blends_rotation_and_scale():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(0.0, Basis.IDENTITY.scaled(Vector3(2, 2, 2)))
	buffer.add_sample(1.0, Basis(Vector3.UP, PI / 2).scaled(Vector3(4, 4, 4)))

	var halfway: Basis = buffer.sample_at(0.5)

	assert_almost_eq(halfway.get_scale(), Vector3(3, 3, 3), Vector3.ONE * 0.0001, 'scale blends linearly')
	assert_almost_eq(halfway.get_rotation_quaternion().get_angle(), PI / 4, 0.0001, 'rotation blends, not held')
	assert_almost_eq(halfway.get_rotation_quaternion().get_axis().abs(), Vector3.UP, Vector3.ONE * 0.0001)


func test_a_non_normalized_quaternion_blends_as_its_rotation():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(0.0, Quaternion.IDENTITY * 2.0)
	buffer.add_sample(1.0, Quaternion(Vector3.UP, PI / 2) * 3.0)

	var halfway: Quaternion = buffer.sample_at(0.5)

	assert_true(halfway.is_normalized(), 'the result is a unit quaternion')
	assert_almost_eq(halfway.get_angle(), PI / 4, 0.0001)


func test_previous_time_outside_the_gap_adds_no_hold_sample():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(1.0, 0.0)
	buffer.add_sample(3.0, 2.0, 0.5)
	buffer.add_sample(4.0, 3.0, 4.0)
	assert_eq(buffer.size(), 3)
	buffer.add_sample(6.0, 5.0, 5.0)
	assert_eq(buffer.size(), 5, 'a previous_time between the newest sample and the new one holds the old value')
	assert_eq(buffer.sample_at(4.5), 3.0)


func test_clear_drops_everything():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(1.0, 1.0)
	buffer.clear()
	assert_true(buffer.is_empty())
	assert_eq(buffer.latest_time(), -INF)


func test_degenerate_rotations_and_transforms_are_held():
	var cases := [
		[Quaternion(0, 0, 0, 0), Quaternion.IDENTITY],
		[Quaternion.IDENTITY, Quaternion(0, 0, 0, 0)],
		[Basis.IDENTITY, Basis(Vector3.RIGHT, Vector3.ZERO, Vector3.BACK)],
		[Basis(Vector3.RIGHT, Vector3.ZERO, Vector3.BACK), Basis.IDENTITY],
		[Transform2D(Vector2.ZERO, Vector2.UP, Vector2.ZERO), Transform2D()],
		[Transform3D(Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK), Vector3.ZERO), Transform3D(Basis(), Vector3.ONE)],
	]
	for c in cases:
		var buffer := LFInterpolationBuffer.new()
		buffer.add_sample(0.0, c[0])
		buffer.add_sample(1.0, c[1])
		assert_eq(buffer.sample_at(0.5), c[0], 'a collapsed %s holds the earlier value' % type_string(typeof(c[0])))


## A unit spawning in grows from almost nothing: a tiny scale is not a collapsed basis.
func test_a_tiny_but_valid_scale_still_blends():
	var basis := LFInterpolationBuffer.new()
	basis.add_sample(0.0, Basis.IDENTITY.scaled(Vector3.ONE * 0.01))
	basis.add_sample(1.0, Basis.IDENTITY)
	assert_almost_eq(basis.sample_at(0.5).get_scale(), Vector3.ONE * 0.505, Vector3.ONE * 0.0001)
	var transform := LFInterpolationBuffer.new()
	transform.add_sample(0.0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.01), Vector3.ZERO))
	transform.add_sample(1.0, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	var halfway: Transform3D = transform.sample_at(0.5)
	assert_almost_eq(halfway.origin, Vector3(1, 0, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(halfway.basis.get_scale(), Vector3.ONE * 0.505, Vector3.ONE * 0.0001)
	var flat := LFInterpolationBuffer.new()
	flat.add_sample(0.0, Transform2D(0.0, Vector2.ONE * 0.001, 0.0, Vector2.ZERO))
	flat.add_sample(1.0, Transform2D(0.0, Vector2(4, 0)))
	assert_almost_eq(flat.sample_at(0.5).origin, Vector2(2, 0), Vector2.ONE * 0.0001)


func test_a_zero_correction_rate_never_closes_a_small_drift():
	clock = LFPlaybackClock.new(0.1, 0.0, 0.5)
	clock.stamp(1.0)
	clock.stamp(1.3) # wanted 1.2, playback 0.9

	assert_almost_eq(clock.advance(0.1), 1.0, 0.0001, 'real speed only')


func test_a_correction_never_overshoots_the_wanted_time():
	clock = LFPlaybackClock.new(0.1, 50.0, 10.0)
	clock.stamp(1.0)
	clock.stamp(3.0) # wanted 2.9, playback 0.9

	assert_almost_eq(clock.advance(0.1), 2.9, 0.0001, 'a correction above the whole gap closes exactly the gap')


func test_sampling_exactly_at_a_stamp_gives_that_sample():
	var buffer := LFInterpolationBuffer.new()
	buffer.add_sample(1.0, 10.0)
	buffer.add_sample(2.0, 20.0)
	buffer.add_sample(3.0, 30.0)
	assert_eq(buffer.sample_at(2.0), 20.0)
	assert_eq(buffer.size(), 2, 'the sample before it is dropped')


## Inf or NaN anywhere in a sample (a corrupt or hostile update) never reaches the
## blending maths: the sample is refused with a warning and the last good value plays on.
func test_a_sample_that_is_not_finite_is_refused_and_the_last_good_value_holds():
	var good := {
		'v3': Vector3(1, 2, 3), 'q': Quaternion.IDENTITY, 'b': Basis.IDENTITY,
		't3': Transform3D.IDENTITY, 't2': Transform2D.IDENTITY, 'f': 1.0, 'c': Color.RED,
	}
	var bad := {
		'v3': [Vector3(INF, 0, 0), Vector3(NAN, 0, 0)],
		'q': [Quaternion(INF, 0, 0, 1), Quaternion(NAN, NAN, NAN, NAN), Quaternion(0, 0, 0, -INF)],
		'b': [Basis(Vector3(INF, 0, 0), Vector3.UP, Vector3.BACK), Basis(Vector3(NAN, 0, 0), Vector3(0, NAN, 0), Vector3(0, 0, NAN))],
		't3': [Transform3D(Basis(Vector3(INF, 0, 0), Vector3.UP, Vector3.BACK), Vector3.ZERO), Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))],
		't2': [Transform2D(NAN, Vector2.ZERO), Transform2D(0.0, Vector2(INF, 1))],
		'f': [INF, NAN, -INF],
		'c': [Color(NAN, 0, 0)],
	}
	for kind in good:
		for value in bad[kind]:
			var buffer := LFInterpolationBuffer.new()
			buffer.add_sample(1.0, good[kind])
			buffer.add_sample(2.0, value)
			buffer.add_sample(NAN, good[kind])
			assert_eq(buffer.size(), 1, '%s %s' % [kind, value])
			assert_eq(buffer.sample_at(1.5), good[kind], kind)
			assert_eq(buffer.sample_at(3.0), good[kind], kind)
			buffer.add_sample(3.0, good[kind])
			assert_eq(buffer.size(), 2, 'a finite sample is still taken after a refused one')
	assert_push_warning('not finite')
	assert_engine_error_count(0)


## Finite but huge values (vectors hold 32-bit floats), whose squared lengths overflow,
## are held instead of blended.
func test_finite_values_too_large_to_measure_are_held_without_engine_errors():
	var cases := [
		[Quaternion(1e20, 1e20, 0, 0), Quaternion.IDENTITY],
		[Basis(Vector3(1e20, 0, 0), Vector3(0, 1e20, 0), Vector3(0, 0, 1e20)), Basis.IDENTITY],
		[Transform3D(Basis(Vector3(1e20, 0, 0), Vector3(0, 1e20, 0), Vector3(0, 0, 1e20)), Vector3.ZERO), Transform3D.IDENTITY],
		[Transform2D(Vector2(1e20, 0), Vector2(0, 1e20), Vector2.ZERO), Transform2D.IDENTITY],
	]
	for pair in cases:
		var buffer := LFInterpolationBuffer.new()
		buffer.add_sample(1.0, pair[0])
		buffer.add_sample(2.0, pair[1])
		assert_eq(buffer.sample_at(1.5), pair[0], str(pair[0]))
	assert_engine_error_count(0)


func test_is_finite_value_checks_every_blended_type_and_passes_the_rest():
	assert_false(LFInterpolationBuffer.is_finite_value(Vector4(0, 0, 0, NAN)))
	assert_false(LFInterpolationBuffer.is_finite_value(Vector2(-INF, 0)))
	assert_true(LFInterpolationBuffer.is_finite_value(Vector3(1e30, 0, 0)))
	assert_true(LFInterpolationBuffer.is_finite_value('text'))
	assert_true(LFInterpolationBuffer.is_finite_value(7))


func test_a_stamp_that_is_not_finite_is_ignored():
	clock.stamp(INF)
	assert_false(clock.is_started())

	clock.stamp(NAN)
	assert_false(clock.is_started())

	clock.stamp(1.0)
	clock.stamp(INF)
	assert_eq(clock.latest, 1.0, 'an infinite stamp does not become the newest')
