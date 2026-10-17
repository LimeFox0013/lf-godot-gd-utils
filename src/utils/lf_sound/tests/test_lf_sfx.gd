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
