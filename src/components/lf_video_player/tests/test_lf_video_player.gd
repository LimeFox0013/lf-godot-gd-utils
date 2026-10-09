extends GutTest

## A stand-in stream whose playback plays, pauses, seeks and advances like a real video,
## so playback can be observed without video media.
class FakeStream extends VideoStream:
	func _instantiate_playback() -> VideoStreamPlayback:
		return FakePlayback.new()


class FakePlayback extends VideoStreamPlayback:
	var playing := false
	var paused := false
	var position := 0.0
	var texture := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))

	func _play() -> void:
		playing = true
		position = 0.0

	func _stop() -> void:
		playing = false
		position = 0.0

	func _is_playing() -> bool:
		return playing

	func _set_paused(value: bool) -> void:
		paused = value

	func _is_paused() -> bool:
		return paused

	func _get_length() -> float:
		return 100.0

	func _get_playback_position() -> float:
		return position

	func _seek(time: float) -> void:
		position = time

	func _update(delta: float) -> void:
		if playing and !paused:
			position += delta

	func _get_texture() -> Texture2D:
		return texture

	func _get_channels() -> int:
		return 2

	func _get_mix_rate() -> int:
		return 44100


## A short stream whose playback stops by itself at its end, as a real video does.
class ShortStream extends VideoStream:
	func _instantiate_playback() -> VideoStreamPlayback:
		return ShortPlayback.new()


class ShortPlayback extends FakePlayback:
	const LENGTH := 0.3

	func _get_length() -> float:
		return LENGTH

	func _update(delta: float) -> void:
		super._update(delta)
		if position >= LENGTH:
			playing = false


## A short stream that reports no length, as some formats do.
class NoLengthStream extends VideoStream:
	func _instantiate_playback() -> VideoStreamPlayback:
		return NoLengthPlayback.new()


class NoLengthPlayback extends ShortPlayback:
	func _get_length() -> float:
		return 0.0


var player: LFVideoPlayer


func before_each():
	player = add_child_autofree(LFVideoPlayer.new())
	player.stream = FakeStream.new()


func after_each():
	get_tree().paused = false


## Waits whole process frames until their deltas add up to `seconds`: the time the
## player's own `_process` sees, whatever the frame rate.
func _wait_process_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func test_start_at_plays_from_the_given_millisecond_and_can_clear_a_pause():
	player.pause()

	player.start_at(1500.0, true)

	assert_true(player.is_playing())
	assert_false(player.paused)
	assert_almost_eq(player.stream_position, 1.5, 0.001)


func test_pause_and_unpause_toggle_the_paused_flag():
	player.pause()
	assert_true(player.paused)
	player.unpause()
	assert_false(player.paused)


func test_the_controls_return_the_player_for_chaining():
	assert_same(player.start_at(0.0), player)
	assert_same(player.pause(), player)
	assert_same(player.unpause(), player)


func test_play_for_is_a_coroutine_that_resolves_to_the_player_once_the_time_elapses():
	var results := []
	var run := func(): results.append(await player.play_for(50.0))

	run.call()
	assert_eq(results, [], 'play_for must not resolve before its time is up')

	await wait_until(func(): return results.size() == 1, 5.0)
	assert_same(results[0], player, 'play_for returns the player for chaining')


func test_play_for_clears_a_prior_pause_and_pauses_when_the_time_runs_out():
	player.pause()
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))

	player.play_for(50.0)
	assert_false(player.paused, 'play_for unpauses while it plays')

	await wait_until(func(): return player.paused, 5.0)
	assert_true(player.paused, 'play_for pauses once its time runs out')
	assert_eq(finished, [true])
	assert_gte(player.stream_position, 0.05, 'the segment lasted its length in video time')


func test_play_for_starts_from_the_given_millisecond():
	player.play_for(1000.0, 2000.0)

	assert_almost_eq(player.stream_position, 2.0, 0.001)


func test_a_newer_start_ends_the_older_segment_without_pausing():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	var done := [false]
	var run := func():
		await player.play_for(50.0)
		done[0] = true
	run.call()

	player.start_at(0.0, true)

	await wait_until(func(): return done[0], 5.0)
	assert_true(done[0], 'the older play_for resolves at once')
	assert_eq(finished, [false])
	for i in 10:
		await get_tree().process_frame
	assert_false(player.paused, 'an outdated play_for never pauses a newer playback')


func test_stop_during_play_for_ends_the_segment_and_leaves_the_player_ready_to_play():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	player.play_for(50.0)

	player.stop()
	await wait_until(func(): return !finished.is_empty(), 5.0)
	await wait_process_frames(5)

	assert_eq(finished, [false])
	assert_false(player.paused, 'a stopped player is not left paused')
	player.play()
	assert_true(player.is_playing())


## The segment is well under way (0.3 s in) before the restart, so even a slow frame
## after play() reads as the position stepping back; once the restarted playback is past
## 0.6 s the old segment would have run out and paused the player had it not ended.
func test_a_native_play_during_play_for_counts_as_a_restart():
	player.play_for(600.0)
	await wait_until(func(): return player.stream_position > 0.3, 5.0)

	player.play()
	await wait_until(func(): return player.stream_position > 0.65, 5.0)

	assert_false(player.paused, 'the restarted playback is not paused by the old segment')
	assert_true(player.is_playing())


func test_a_new_stream_during_play_for_ends_the_segment():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	player.play_for(50.0)

	player.stream = FakeStream.new()
	player.play()
	await wait_until(func(): return !finished.is_empty(), 5.0)
	await wait_process_frames(5)

	assert_eq(finished, [false])
	assert_false(player.paused)


func test_a_tree_pause_holds_the_segment_clock():
	player.play_for(100.0)
	get_tree().paused = true

	await _wait_process_seconds(0.3)
	assert_false(player.paused, 'the segment does not run out while the tree is paused')

	get_tree().paused = false
	await wait_until(func(): return player.paused, 5.0)
	assert_true(player.paused, 'it runs out once the tree resumes')


func test_freeing_the_player_resolves_its_play_for():
	var results := []
	var run := func(): results.append(await player.play_for(5000.0))
	run.call()

	player.free()

	assert_eq(results.size(), 1, 'a caller awaiting play_for is not left hanging')


func test_a_negative_duration_is_rejected():
	var results := []
	var run := func(): results.append(await player.play_for(-500.0))
	run.call()

	assert_push_error('play_for')
	assert_eq(results.size(), 1, 'play_for returns at once')
	assert_false(player.is_playing(), 'nothing was started')


func test_pausing_the_player_holds_the_segment_clock():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	player.play_for(100.0)
	player.pause()

	await _wait_process_seconds(0.3)
	assert_eq(finished, [], 'a paused video does not use up the segment')

	player.unpause()
	await wait_until(func(): return finished.size() == 1, 5.0)
	assert_eq(finished, [true])
	assert_true(player.paused)


func test_removing_the_player_from_the_tree_ends_the_segment_cut_short():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	var results := []
	var run := func(): results.append(await player.play_for(5000.0))
	run.call()

	remove_child(player)

	assert_eq(finished, [false])
	assert_eq(results.size(), 1, 'the coroutine returned at once')
	add_child(player)


func test_start_at_without_force_unpause_keeps_a_pause():
	player.pause()

	player.start_at(500.0)

	assert_true(player.paused)
	assert_almost_eq(player.stream_position, 0.5, 0.001)


func test_a_player_outside_the_tree_reports_instead_of_starting_or_hanging():
	var loose: LFVideoPlayer = autofree(LFVideoPlayer.new())
	loose.stream = FakeStream.new()
	var results := []
	var run := func(): results.append(await loose.play_for(50.0))

	assert_same(loose.start_at(100.0), loose)
	run.call()

	assert_push_error_count(2)
	assert_engine_error_count(0, 'no engine error from play() outside the tree')
	assert_eq(results.size(), 1, 'play_for returns at once instead of waiting forever')
	assert_false(loose.is_playing())


func test_a_nan_duration_is_rejected():
	var results := []
	var run := func(): results.append(await player.play_for(NAN))
	run.call()

	assert_push_error('play_for')
	assert_eq(results.size(), 1, 'play_for returns at once instead of never finishing')
	assert_false(player.is_playing())


## A looping stream jumps back to 0 at its end; that wrap is playback, not a restart.
func test_a_segment_runs_on_through_a_loop_wrap():
	player.stream = ShortStream.new()
	player.loop = true
	var results := []
	player.segment_finished.connect(func(completed: bool): results.append(completed))

	await player.play_for(500.0, 0.0)

	assert_eq(results, [true], 'the segment ran its full time across the loop point')
	assert_true(player.paused)
	assert_lt(player.stream_position, ShortPlayback.LENGTH, 'it wrapped before pausing')
	# play_for resumed inside the player's own _process; let it return before the player is freed.
	await wait_process_frames(1)


func test_an_idle_player_does_not_process():
	assert_false(player.is_processing())


func test_seeking_back_during_play_for_ends_the_segment_cut_short():
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	player.play_for(5000.0, 2000.0)
	await wait_process_frames(2)

	player.stream_position = 0.5
	await wait_until(func(): return !finished.is_empty(), 5.0)

	assert_eq(finished, [false])
	assert_false(player.paused)
	assert_false(player.is_processing(), 'nothing left to count')


func test_with_loop_on_a_seek_back_far_from_the_end_still_ends_the_segment():
	player.loop = true
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))
	player.play_for(5000.0, 2000.0)
	await wait_process_frames(2)

	player.stream_position = 0.5
	await wait_until(func(): return !finished.is_empty(), 5.0)

	assert_eq(finished, [false], 'only a jump back from the end is a wrap')


func test_a_loop_wrap_of_a_stream_without_a_length_ends_the_segment():
	player.stream = NoLengthStream.new()
	player.loop = true
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))

	await player.play_for(5000.0, 0.0)

	assert_eq(finished, [false], 'without a length the wrap reads as a restart')
	assert_false(player.paused)
	await wait_process_frames(1)


func test_a_stream_ending_by_itself_ends_the_segment_cut_short():
	player.stream = ShortStream.new()
	var finished := []
	player.segment_finished.connect(func(completed: bool): finished.append(completed))

	await player.play_for(5000.0, 0.0)

	assert_eq(finished, [false])
	assert_false(player.is_playing())
	await wait_process_frames(1)


func test_a_zero_duration_pauses_at_the_players_next_process():
	var finished := []
	var finished_frames := []
	player.segment_finished.connect(func(completed: bool):
		finished.append(completed)
		finished_frames.append(Engine.get_process_frames()))
	var frame := Engine.get_process_frames()

	player.play_for(0.0, 1000.0)
	assert_eq(finished, [], 'not within the call')
	assert_false(player.paused)
	await wait_until(func(): return not finished.is_empty(), 5.0)

	assert_lte(finished_frames[0] - frame, 1, 'by the next frame at the latest')
	assert_eq(finished, [true])
	assert_true(player.paused)
	await wait_process_frames(1)


func test_play_for_without_a_start_continues_from_the_current_position():
	player.start_at(3000.0)
	player.pause()

	player.play_for(5000.0)

	assert_false(player.paused)
	assert_almost_eq(player.stream_position, 3.0, 0.001)


func test_a_segment_started_on_tree_entered_survives_the_players_ready():
	var fresh := LFVideoPlayer.new()
	fresh.stream = FakeStream.new()
	var finished: Array = []
	fresh.segment_finished.connect(func(completed: bool) -> void: finished.append(completed))
	fresh.tree_entered.connect(func() -> void: fresh.play_for(100.0, 0.0))
	add_child_autofree(fresh)

	await _wait_process_seconds(0.4)

	assert_eq(finished, [true], 'the segment must finish; _ready must not switch _process off')
