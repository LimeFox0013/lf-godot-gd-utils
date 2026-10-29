## Makes short sound effects from nothing: a tone, a sweep or a puff of noise, as a ready `AudioStreamWAV`.
##
## For a prototype with no sound files, or small bleeps and thuds that need no art: `LFTone.make(440.0, 0.1)` is
## a tenth of a second at 440 Hz. A sweep (`end_frequency`) gives a jump or a drop; `Wave.NOISE` gives a thud or
## a hiss. The same arguments always give the same samples. Play the result with `LFSfx` or any audio player.
class_name LFTone
extends RefCounted

enum Wave { SINE, SQUARE, TRIANGLE, NOISE }

## Samples per second when none is given.
const DEFAULT_RATE := 22050
## Seconds the sound takes to reach its full volume, when none is given (a click-free start).
const DEFAULT_ATTACK := 0.005
const _PEAK := 32767.0


## A mono 16-bit sound of `seconds`. The pitch glides from `frequency` to `end_frequency` (0 or less: stays at
## `frequency`); `volume` is 0 to 1; the sound fades out over its whole length. A length of 0 or less, or a
## `frequency` of 0 or less (except for noise), gives an empty sound.
static func make(frequency: float, seconds: float, wave: Wave = Wave.SINE, volume: float = 0.5, end_frequency: float = 0.0, attack: float = DEFAULT_ATTACK, rate: int = DEFAULT_RATE) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = maxi(rate, 1)
	stream.stereo = false
	stream.data = samples(frequency, seconds, wave, volume, end_frequency, attack, rate)
	return stream


## The 16-bit little-endian samples `make` puts in the sound, for a caller that wants the raw data.
static func samples(frequency: float, seconds: float, wave: Wave = Wave.SINE, volume: float = 0.5, end_frequency: float = 0.0, attack: float = DEFAULT_ATTACK, rate: int = DEFAULT_RATE) -> PackedByteArray:
	var data := PackedByteArray()
	var count := int(seconds * float(rate))
	if count <= 0 or rate <= 0 or (wave != Wave.NOISE and frequency <= 0.0):
		return data
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var phase := 0.0
	var peak := clampf(volume, 0.0, 1.0) * _PEAK
	var attack_samples := maxf(attack * float(rate), 1.0)
	for i in count:
		var t := float(i) / float(count)
		var hz := frequency if end_frequency <= 0.0 else lerpf(frequency, end_frequency, t)
		phase = fposmod(phase + hz / float(rate), 1.0)
		var level := minf(float(i) / attack_samples, 1.0) * (1.0 - t)
		data.encode_s16(i * 2, int(_wave_at(wave, phase, rng) * level * peak))
	return data


static func _wave_at(wave: Wave, phase: float, rng: RandomNumberGenerator) -> float:
	match wave:
		Wave.SQUARE:
			return 1.0 if phase < 0.5 else -1.0
		Wave.TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
		Wave.NOISE:
			return rng.randf_range(-1.0, 1.0)
		_:
			return sin(TAU * phase)
