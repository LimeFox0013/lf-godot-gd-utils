extends GutTest


func test_length_follows_seconds_and_rate() -> void:
	var stream := LFTone.make(440.0, 0.1, LFTone.Wave.SINE, 0.5, 0.0, 0.005, 10000)
	assert_eq(stream.data.size(), 1000 * 2)
	assert_eq(stream.mix_rate, 10000)
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)


func test_same_arguments_give_the_same_samples() -> void:
	for wave in [LFTone.Wave.SINE, LFTone.Wave.SQUARE, LFTone.Wave.TRIANGLE, LFTone.Wave.NOISE]:
		assert_eq(LFTone.samples(300.0, 0.05, wave), LFTone.samples(300.0, 0.05, wave))


func test_the_sound_fades_out_to_silence() -> void:
	var data := LFTone.samples(200.0, 0.2, LFTone.Wave.SQUARE, 1.0)
	assert_lt(absi(data.decode_s16(data.size() - 2)), 300, 'the last sample is nearly silent')
	var loudest := 0
	for i in range(0, data.size(), 2):
		loudest = maxi(loudest, absi(data.decode_s16(i)))
	assert_gt(loudest, 20000)


func test_volume_scales_the_loudest_sample() -> void:
	var loud := LFTone.samples(200.0, 0.1, LFTone.Wave.SQUARE, 1.0)
	var quiet := LFTone.samples(200.0, 0.1, LFTone.Wave.SQUARE, 0.25)
	var loud_peak := 0
	var quiet_peak := 0
	for i in range(0, loud.size(), 2):
		loud_peak = maxi(loud_peak, absi(loud.decode_s16(i)))
		quiet_peak = maxi(quiet_peak, absi(quiet.decode_s16(i)))
	assert_almost_eq(float(quiet_peak) / float(loud_peak), 0.25, 0.02)


func test_a_sweep_differs_from_a_steady_tone() -> void:
	assert_ne(LFTone.samples(200.0, 0.1, LFTone.Wave.SINE, 0.5, 800.0), LFTone.samples(200.0, 0.1))


func test_nothing_to_play_gives_an_empty_sound() -> void:
	assert_eq(LFTone.make(440.0, 0.0).data.size(), 0)
	assert_eq(LFTone.make(0.0, 0.1).data.size(), 0)
	assert_gt(LFTone.make(0.0, 0.1, LFTone.Wave.NOISE).data.size(), 0, 'noise needs no pitch')


func test_samples_match_the_stream_data() -> void:
	assert_eq(LFTone.make(440.0, 0.05).data, LFTone.samples(440.0, 0.05))


func test_a_sweep_to_zero_or_less_keeps_the_pitch() -> void:
	assert_eq(LFTone.samples(300.0, 0.05, LFTone.Wave.SINE, 0.5, -5.0), LFTone.samples(300.0, 0.05))


func test_volume_is_clamped_to_one() -> void:
	assert_eq(LFTone.samples(200.0, 0.05, LFTone.Wave.SQUARE, 5.0), LFTone.samples(200.0, 0.05, LFTone.Wave.SQUARE, 1.0))


func test_a_bad_rate_gives_an_empty_sound() -> void:
	assert_eq(LFTone.make(440.0, 0.1, LFTone.Wave.SINE, 0.5, 0.0, 0.005, 0).data.size(), 0)


func test_the_start_ramps_up_over_the_attack() -> void:
	var data := LFTone.samples(200.0, 0.2, LFTone.Wave.SQUARE, 1.0, 0.0, 0.05)
	assert_lt(absi(data.decode_s16(2)), 2000, 'second sample is still quiet')
