extends GutTest

var _sfx: LFSfx


func before_each() -> void:
	_sfx = LFSfx.new()
	_sfx.voices = 2
	add_child_autofree(_sfx)


func test_a_null_stream_is_refused() -> void:
	assert_false(_sfx.play(null))


func test_sounds_overlap_up_to_the_voices() -> void:
	var stream := LFTone.make(440.0, 1.0)
	assert_true(_sfx.play(stream))
	assert_true(_sfx.play(stream))
	assert_eq(_sfx.busy_count(), 2)


func test_a_third_sound_cuts_the_oldest_when_all_are_busy() -> void:
	var stream := LFTone.make(440.0, 1.0)
	_sfx.play(stream)
	_sfx.play(stream)
	assert_true(_sfx.play(stream))
	assert_eq(_sfx.busy_count(), 2)


func test_pitch_and_volume_apply_to_the_play() -> void:
	_sfx.play(LFTone.make(440.0, 1.0), -6.0, 1.5)
	var player := _sfx.get_child(0) as AudioStreamPlayer
	assert_eq(player.volume_db, -6.0)
	assert_eq(player.pitch_scale, 1.5)


func test_play_before_entering_the_tree_is_refused() -> void:
	var loose := LFSfx.new()
	assert_false(loose.play(LFTone.make(440.0, 0.1)))
	loose.free()


func test_pool_size_follows_voices_and_bus() -> void:
	var sfx := LFSfx.new()
	sfx.voices = 3
	sfx.bus = &"Master"
	add_child_autofree(sfx)
	assert_eq(sfx.get_child_count(), 3)
	assert_eq((sfx.get_child(0) as AudioStreamPlayer).bus, &"Master")


func test_zero_voices_still_makes_one_player() -> void:
	var sfx := LFSfx.new()
	sfx.voices = 0
	add_child_autofree(sfx)
	assert_eq(sfx.get_child_count(), 1)


func test_pitch_jitter_stays_within_its_range() -> void:
	_sfx.pitch_jitter = 0.1
	var player := _sfx.get_child(0) as AudioStreamPlayer
	for i in 20:
		_sfx.play(LFTone.make(440.0, 0.05))
		assert_between(player.pitch_scale, 0.9 - 0.0001, 1.1 + 0.0001)
		player.stop()


func test_pitch_is_never_zero_or_negative() -> void:
	_sfx.play(LFTone.make(440.0, 0.1), 0.0, -2.0)
	assert_gt((_sfx.get_child(0) as AudioStreamPlayer).pitch_scale, 0.0)
