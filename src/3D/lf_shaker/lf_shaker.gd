## Screen shake for a camera (or any Node3D): jolts, impacts and rumbles that stack and settle.
##
## Put it between a rig and the camera (`Rig/LFShaker/Camera3D`) and call `shake` or
## `add_trauma`. Every frame it moves itself by a smooth random ("noise") offset of
## position and rotation around its rest transform, captured when a shake starts, then,
## with `auto_reset_on_idle` on (the default), settles back exactly to rest. Two models:
## "trauma" (a 0..1 shake level that adds up and fades out over time) or "fixed duration"
## (each shake runs for its own number of seconds). Offsets never accumulate; an idle shaker never writes its transform.
class_name LFShaker
extends Node3D

## Default `trauma_decay_rate`, trauma lost per second (a full shake fades in 0.4 s).
const DEFAULT_TRAUMA_DECAY_RATE := 2.5
## Default `trauma_exponent` (intensity is trauma to this power; 2 is the classic feel).
const DEFAULT_TRAUMA_EXPONENT := 2.0
## Default `translation_strength`, the positional offset per axis at intensity 1, in the
## parent's units.
const DEFAULT_TRANSLATION_STRENGTH := Vector3(0.1, 0.1, 0.1)
## Default `translation_frequency`, in Hz.
const DEFAULT_TRANSLATION_FREQUENCY := 8.0
## Default `rotation_strength_deg`, the rotation per axis at intensity 1, in degrees.
const DEFAULT_ROTATION_STRENGTH_DEG := Vector3(2.0, 2.0, 2.0)
## Default `rotation_frequency`, in Hz.
const DEFAULT_ROTATION_FREQUENCY := 10.0
## Default `seed_value` of the noise generator.
const DEFAULT_SEED := 12345
## Default `noise_roughness`, 0 (smooth) .. 1 (rough).
const DEFAULT_NOISE_ROUGHNESS := 0.5
## Default `idle_trauma_threshold`, an intensity below which the shake ends.
const DEFAULT_IDLE_TRAUMA_THRESHOLD := 0.001
## Default `magnitude` of `shake` (and of a `Profile`), 0..1.
const DEFAULT_MAGNITUDE := 0.5
## Default `duration` of `shake` (and of a `Profile`), in seconds.
const DEFAULT_DURATION := 0.2

## Inspector minimum of `trauma_decay_rate`, in trauma per second.
const _DECAY_RATE_MIN := 0.1
## Inspector maximum of `trauma_decay_rate`, in trauma per second.
const _DECAY_RATE_MAX := 10.0
## Inspector step of `trauma_decay_rate`.
const _DECAY_RATE_STEP := 0.01
## Inspector minimum of `trauma_exponent`.
const _EXPONENT_MIN := 0.5
## Inspector maximum of `trauma_exponent`.
const _EXPONENT_MAX := 4.0
## Inspector step of `trauma_exponent`.
const _EXPONENT_STEP := 0.01
## Inspector minimum of `translation_frequency` and `rotation_frequency`, in Hz.
const _FREQUENCY_MIN := 0.1
## Inspector maximum of `translation_frequency` and `rotation_frequency`, in Hz.
const _FREQUENCY_MAX := 30.0
## Inspector step of `translation_frequency` and `rotation_frequency`, in Hz.
const _FREQUENCY_STEP := 0.1
## Inspector step of `noise_roughness` (its range is 0..1).
const _ROUGHNESS_STEP := 0.01
## Inspector maximum of `idle_trauma_threshold` (its minimum is 0).
const _IDLE_THRESHOLD_MAX := 0.1
## Inspector step of `idle_trauma_threshold`.
const _IDLE_THRESHOLD_STEP := 0.001

## Noise frequency of the generator: 1, so the frequency properties alone set the speed.
const _NOISE_FREQUENCY := 1.0
## Fractal octaves at roughness 0.
const _SMOOTH_OCTAVES := 1.0
## Fractal octaves at roughness 1.
const _ROUGH_OCTAVES := 3.0
## Frequency multiplier between octaves.
const _NOISE_LACUNARITY := 2.0
## Fractal gain (detail strength) at roughness 0.
const _SMOOTH_GAIN := 0.3
## Fractal gain (detail strength) at roughness 1.
const _ROUGH_GAIN := 0.6
## Noise offset (in noise time) of translation X; each axis has its own, so the axes move
## independently.
const _TRANSLATION_NOISE_OFFSET_X := 37.1
## Noise offset of translation Y.
const _TRANSLATION_NOISE_OFFSET_Y := 91.7
## Noise offset of translation Z.
const _TRANSLATION_NOISE_OFFSET_Z := 159.3
## Noise offset of rotation X (pitch).
const _ROTATION_NOISE_OFFSET_X := 11.1
## Noise offset of rotation Y (yaw).
const _ROTATION_NOISE_OFFSET_Y := 53.8
## Noise offset of rotation Z (roll).
const _ROTATION_NOISE_OFFSET_Z := 204.6

## Master switch. Turning it off stops a running shake and returns the node to rest; a
## disabled shaker ignores shakes.
@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		enabled = value
		if not value:
			stop_shake()

@export_group("Shake Model")
## True: the trauma model, where trauma (the 0..1 shake level) adds up and fades by
## `trauma_decay_rate` per second. False: the fixed-duration model, where each `shake`
## holds its strength for its own duration, then stops.
@export var use_trauma_model: bool = true

## Trauma lost per second under the trauma model: 2.5 fades a full shake in 0.4 s.
@export_range(_DECAY_RATE_MIN, _DECAY_RATE_MAX, _DECAY_RATE_STEP)
var trauma_decay_rate: float = DEFAULT_TRAUMA_DECAY_RATE

## Shake intensity is `pow(trauma_value, trauma_exponent)`. Above 1, small trauma barely
## shakes and big trauma shakes hard; 2 is the classic feel.
@export_range(_EXPONENT_MIN, _EXPONENT_MAX, _EXPONENT_STEP)
var trauma_exponent: float = DEFAULT_TRAUMA_EXPONENT

@export_group("Translation")
## Whether to apply a positional offset.
@export var enable_translation: bool = true
## Positional offset scale per axis at intensity 1, in the parent's units: the most the
## offset can reach. The noise stays within ±1 and mostly well inside it, so the offset
## seldom gets there.
@export var translation_strength: Vector3 = DEFAULT_TRANSLATION_STRENGTH
## Speed of the translation noise in Hz: roughly how many swings per second. Above about
## 15 Hz a swing gets 4 frames or fewer at 60 fps, so the motion reads as jitter.
@export_range(_FREQUENCY_MIN, _FREQUENCY_MAX, _FREQUENCY_STEP)
var translation_frequency: float = DEFAULT_TRANSLATION_FREQUENCY

@export_group("Rotation")
## Whether to apply a rotational offset.
@export var enable_rotation: bool = true
## Rotation scale per axis at intensity 1, in degrees, about the node's own axes
## (x pitch, y yaw, z roll): the most the rotation can reach, as `translation_strength`.
@export var rotation_strength_deg: Vector3 = DEFAULT_ROTATION_STRENGTH_DEG
## Speed of the rotation noise in Hz, as `translation_frequency`.
@export_range(_FREQUENCY_MIN, _FREQUENCY_MAX, _FREQUENCY_STEP)
var rotation_frequency: float = DEFAULT_ROTATION_FREQUENCY

@export_group("Noise")
## Seed for the FastNoiseLite generator. Shakers with the same seed sample the same
## noise, so two with the same settings and the same `time_counter` move identically.
## Setting it rebuilds the noise.
@export var seed_value: int = DEFAULT_SEED:
	set(value):
		seed_value = value
		setup_noise()

## Texture of the noise, from smooth (0, one octave) to rough (1, three octaves with
## stronger detail). It never changes the speed. Setting it rebuilds the noise.
@export_range(0.0, 1.0, _ROUGHNESS_STEP)
var noise_roughness: float = DEFAULT_NOISE_ROUGHNESS:
	set(value):
		noise_roughness = value
		setup_noise()

@export_group("Behavior")
## Restore `original_transform` once, when a shake ends (the transition to idle). Off:
## the last shaken frame stays.
@export var auto_reset_on_idle: bool = true
## Intensity below this counts as idle: the shake ends and the trauma is zeroed.
@export_range(0.0, _IDLE_THRESHOLD_MAX, _IDLE_THRESHOLD_STEP)
var idle_trauma_threshold: float = DEFAULT_IDLE_TRAUMA_THRESHOLD

## A reusable bundle of shake settings plus a magnitude and duration ("a heavy impact",
## "a light tremor"), applied with `LFShaker.apply_shake_profile`.
class Profile:
	## Shake strength passed to `shake`, 0..1.
	var magnitude: float
	## Shake duration in seconds (fixed-duration model only).
	var duration: float
	## Trauma lost per second under the trauma model.
	var trauma_decay_rate: float
	## Exponent turning trauma into intensity.
	var trauma_exponent: float
	## Translation noise speed in Hz.
	var translation_frequency: float
	## Rotation noise speed in Hz.
	var rotation_frequency: float
	## Noise roughness, 0..1.
	var noise_roughness: float

	## Builds a profile from the given settings, in the order of its fields; each
	## argument has a default equal to the shaker's own default.
	func _init(
		shake_magnitude := DEFAULT_MAGNITUDE,
		shake_duration := DEFAULT_DURATION,
		decay_rate := DEFAULT_TRAUMA_DECAY_RATE,
		exponent := DEFAULT_TRAUMA_EXPONENT,
		translation_hz := DEFAULT_TRANSLATION_FREQUENCY,
		rotation_hz := DEFAULT_ROTATION_FREQUENCY,
		roughness := DEFAULT_NOISE_ROUGHNESS,
	) -> void:
		magnitude = shake_magnitude
		duration = shake_duration
		trauma_decay_rate = decay_rate
		trauma_exponent = exponent
		translation_frequency = translation_hz
		rotation_frequency = rotation_hz
		noise_roughness = roughness

## Noise generator, built on first use and rebuilt whenever `seed_value` or
## `noise_roughness` is set (or `setup_noise` is called).
var noise_gen: FastNoiseLite
## Seconds this shaker has run while enabled; the noise is sampled at this time.
var time_counter: float = 0.0
## Current trauma (shake level), 0..1. Read it to show or test the shake; set it with
## `set_trauma`, which also captures the rest pose.
var trauma_value: float = 0.0
## Seconds left of the longest running shake under the fixed-duration model; 0 otherwise.
var time_left: float = 0.0

## Rest transform, captured when a shake starts on an idle shaker (and by
## `recapture_original_transform`); every shaken frame is `original_transform` plus that
## frame's offset.
var original_transform: Transform3D
## True while the transform holds a shake offset written by this shaker.
var _is_shaken: bool = false
## Fixed-duration model: the running shakes, each (magnitude, seconds left).
var _timed_shakes: Array[Vector2] = []


func _ready() -> void:
	original_transform = transform


func _process(delta: float) -> void:
	if not enabled:
		return

	time_counter += delta

	var intensity := _advance(delta)
	if intensity <= 0.0 or intensity < idle_trauma_threshold:
		_go_idle()
		return

	var translation_offset := Vector3.ZERO
	var rotation_offset := Vector3.ZERO

	if enable_translation:
		translation_offset = compute_translation(intensity)
	if enable_rotation:
		rotation_offset = compute_rotation(intensity)

	var shaken := original_transform
	shaken.origin += translation_offset

	if rotation_offset != Vector3.ZERO:
		shaken.basis = original_transform.basis * Basis.from_euler(rotation_offset)

	transform = shaken
	_is_shaken = true


## Advances trauma (trauma model) or the remaining time (fixed-duration model) by
## `delta` and returns this frame's intensity; 0 when idle.
func _advance(delta: float) -> float:
	if use_trauma_model:
		if trauma_value <= 0.0:
			return 0.0
		trauma_value = maxf(trauma_value - trauma_decay_rate * delta, 0.0)
	else:
		if _timed_shakes.is_empty():
			return 0.0
		var running: Array[Vector2] = []
		for timed in _timed_shakes:
			if timed.y - delta > 0.0:
				running.append(Vector2(timed.x, timed.y - delta))
		_timed_shakes = running
		_sync_timed_shakes()
		if trauma_value <= 0.0:
			return 0.0
	return pow(trauma_value, trauma_exponent)


## Fixed-duration model: trauma is the strongest running shake, time_left the longest.
func _sync_timed_shakes() -> void:
	trauma_value = 0.0
	time_left = 0.0
	for timed in _timed_shakes:
		trauma_value = maxf(trauma_value, timed.x)
		time_left = maxf(time_left, timed.y)


## The transition to idle: restores original_transform once (with auto_reset_on_idle),
## then leaves the transform alone until the next shake.
func _go_idle() -> void:
	trauma_value = 0.0
	time_left = 0.0
	_timed_shakes.clear()
	if not _is_shaken:
		return
	_is_shaken = false
	if auto_reset_on_idle:
		transform = original_transform


## Adds `amount` to the trauma, clamped to 0..1 (a negative amount calms the shake).
## Ignored while disabled or for a NaN `amount`. Trauma model only: under the
## fixed-duration model the next frame clears it (use `shake`).
func add_trauma(amount: float) -> void:
	if not enabled or is_nan(amount):
		return
	_capture_rest_if_idle()
	trauma_value = clampf(trauma_value + amount, 0.0, 1.0)


## Adds `trauma` scaled by how near `world_pos` (where the jolt happened) is to
## `focus_pos` (usually what the camera looks at): in full at the focus, falling off
## linearly to nothing at `radius` and beyond. With `planar` the distance is measured on
## the XZ plane (height ignored), else in 3D. Ignored while disabled, when `radius` <= 0,
## or when the scaled trauma is 0.
func add_trauma_at(world_pos: Vector3, focus_pos: Vector3, trauma: float, radius: float, planar := true) -> void:
	if radius <= 0.0:
		return
	var distance := Vector2(world_pos.x - focus_pos.x, world_pos.z - focus_pos.z).length() if planar \
		else world_pos.distance_to(focus_pos)
	var nearness := clampf(1.0 - distance / radius, 0.0, 1.0)
	if nearness > 0.0 and trauma != 0.0:
		add_trauma(trauma * nearness)


## Sets the trauma to `value`, clamped to 0..1. Ignored while disabled or for a NaN
## `value`. Trauma model only, as `add_trauma`.
func set_trauma(value: float) -> void:
	if not enabled or is_nan(value):
		return
	_capture_rest_if_idle()
	trauma_value = clampf(value, 0.0, 1.0)


## The everyday call. `magnitude` is clamped to 0..1. Trauma model: `add_trauma(magnitude)`
## (`duration` is ignored; the decay rate sets how long it lasts). Fixed-duration model:
## starts a shake of `magnitude` lasting `duration` seconds alongside any running ones; the
## strongest running shake sets the trauma, so a weaker or shorter shake never weakens or
## shortens another. A zero (or NaN) magnitude or duration does nothing. Ignored while
## disabled.
func shake(magnitude: float = DEFAULT_MAGNITUDE, duration: float = DEFAULT_DURATION) -> void:
	if not enabled:
		return
	var clamped := clampf(magnitude, 0.0, 1.0)
	if use_trauma_model:
		add_trauma(clamped)
		return
	if not (clamped > 0.0 and duration > 0.0):
		return
	_capture_rest_if_idle()
	_timed_shakes.append(Vector2(clamped, duration))
	_sync_timed_shakes()


## Adopts the profile's decay, exponent, frequencies and roughness (rebuilding the noise),
## then shakes with its magnitude and duration. The settings persist for later shakes.
## Applies the settings even while disabled (the shake itself is then ignored).
func apply_shake_profile(shake_profile: Profile) -> void:
	trauma_decay_rate = shake_profile.trauma_decay_rate
	trauma_exponent = shake_profile.trauma_exponent
	translation_frequency = shake_profile.translation_frequency
	rotation_frequency = shake_profile.rotation_frequency
	noise_roughness = shake_profile.noise_roughness
	shake(shake_profile.magnitude, shake_profile.duration)


## Ends every shake now: zeroes trauma and remaining time. With `reset_transform`,
## restores `original_transform` if a shake offset is currently applied; otherwise leaves
## the transform where it is.
func stop_shake(reset_transform: bool = true) -> void:
	trauma_value = 0.0
	time_left = 0.0
	_timed_shakes.clear()
	if reset_transform and _is_shaken:
		transform = original_transform
	_is_shaken = false


## Stores the current transform as the new `original_transform`. A shake captures the rest
## transform by itself when it starts; call this to re-base a shake that is running.
func recapture_original_transform() -> void:
	original_transform = transform


## Takes the current transform as the rest pose when no shake offset is applied, so a node
## moved between shakes shakes around where it now is.
func _capture_rest_if_idle() -> void:
	if not _is_shaken:
		original_transform = transform


## (Re)builds `noise_gen` from `seed_value` and `noise_roughness`. Called for you when
## either is set; call it yourself only after changing `noise_gen` by hand. The noise
## frequency stays 1, so `translation_frequency` and `rotation_frequency` alone set the
## speed in Hz.
func setup_noise() -> void:
	noise_gen = FastNoiseLite.new()
	noise_gen.seed = seed_value
	noise_gen.frequency = _NOISE_FREQUENCY
	noise_gen.fractal_octaves = int(round(lerpf(_SMOOTH_OCTAVES, _ROUGH_OCTAVES, noise_roughness)))
	noise_gen.fractal_lacunarity = _NOISE_LACUNARITY
	noise_gen.fractal_gain = lerpf(_SMOOTH_GAIN, _ROUGH_GAIN, noise_roughness)


func _noise() -> FastNoiseLite:
	if noise_gen == null:
		setup_noise()
	return noise_gen


## Returns the position offset for `intensity` (0..1, usually trauma to the exponent) at
## the current `time_counter`: noise scaled by `translation_strength` and `intensity`.
## Pure: it never moves the node. Works before the node enters the tree.
func compute_translation(intensity: float) -> Vector3:
	var noise := _noise()
	var t := time_counter * translation_frequency

	var n := Vector3(
		noise.get_noise_1d(t + _TRANSLATION_NOISE_OFFSET_X),
		noise.get_noise_1d(t + _TRANSLATION_NOISE_OFFSET_Y),
		noise.get_noise_1d(t + _TRANSLATION_NOISE_OFFSET_Z),
	)
	return n * translation_strength * intensity


## Returns the rotation offset for `intensity` at the current `time_counter`, as Euler
## angles in radians (x pitch, y yaw, z roll) scaled by `rotation_strength_deg` and
## `intensity`; the shaker applies it about its own axes. Pure: it never moves the node.
func compute_rotation(intensity: float) -> Vector3:
	var noise := _noise()
	var t := time_counter * rotation_frequency

	var n := Vector3(
		noise.get_noise_1d(t + _ROTATION_NOISE_OFFSET_X),
		noise.get_noise_1d(t + _ROTATION_NOISE_OFFSET_Y),
		noise.get_noise_1d(t + _ROTATION_NOISE_OFFSET_Z),
	)
	return n * rotation_strength_deg * (deg_to_rad(1.0) * intensity)
