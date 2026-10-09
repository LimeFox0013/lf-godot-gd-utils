## Stores time-stamped values of one thing (a position, a rotation, a colour) and
## gives back a smooth value for any moment between them.
##
## This is the client side of entity interpolation: feed it every stamped update with
## `add_sample`, then each frame read `sample_at(playback_time)` with a playback time that
## trails the newest stamp (see `LFPlaybackClock`). It blends ("interpolates") between the
## two samples around that time.
##
## Playback only moves forward: `sample_at` drops samples it has played past, keeping the
## one just before `time`. Samples must arrive in stamp order; an older or equal stamp is
## ignored. A sample whose stamp or value is not finite (inf or NaN in any component) is
## refused with a pushed warning, so the last good value keeps playing.
class_name LFInterpolationBuffer
extends RefCounted

## Log line prefix.
const _LOG_PREFIX := '[LFInterpolationBuffer]'

static var _log := LFLogger.new([_LOG_PREFIX])

## `[time, value]` pairs, oldest first.
var _samples: Array = []


## Records `value` at `time`. `previous_time` is the stamp of the update before this one:
## a value an update left out did not change, so when this buffer's newest sample is older
## than `previous_time` the old value is also recorded at `previous_time` — without it the
## change would be stretched back over the whole time the value stood still. Leave it out
## (or pass anything not between the newest sample and `time`) when there is none.
## A `time` or `value` that is not finite (inf or NaN in a float, vector, colour,
## quaternion, basis or transform) is not recorded, and a warning is pushed through
## `LFLogger`; values of other types are not checked.
func add_sample(time: float, value: Variant, previous_time: float = -INF) -> void:
	if not is_finite(time) or not is_finite_value(value):
		_log.warning('ignored a sample that is not finite: time %s, value %s' % [time, value])
		return
	if not _samples.is_empty():
		var last: Array = _samples.back()
		if time <= last[0]:
			return
		if previous_time > last[0] and previous_time < time:
			_samples.append([previous_time, last[1]])
	_samples.append([time, value])


## Returns the value at `time`: interpolated between the samples around it (float, Vector2/3/4,
## Color, Quaternion, Basis and Transform2D/3D blend; an int blends to a float; any other
## type, or two samples of different types, holds the earlier value until the next
## sample), the oldest sample before the first one, and the newest after the last. Null
## when empty. Quaternions are normalized before blending (a zero-length one, or one whose
## squared length overflows a float, is held). A
## Basis or Transform blends its rotation (slerp) and its per-axis scale (linearly)
## separately, so a scaled one blends too, however small its scale; shear is not kept. A
## collapsed Basis or Transform (an axis of zero length, axes in one plane, or axes so
## long their volume overflows a float) is held.
func sample_at(time: float) -> Variant:
	while _samples.size() >= 2 and _samples[1][0] <= time:
		_samples.pop_front()
	if _samples.is_empty():
		return null
	var from: Array = _samples[0]
	if _samples.size() == 1 or time <= from[0]:
		return from[1]
	var to: Array = _samples[1]
	return _blend(from[1], to[1], (time - from[0]) / (to[0] - from[0]))


## Returns `false` when `value` is a float, Vector2/3/4, Color, Quaternion, Basis or
## Transform2D/3D with an inf or NaN component; `true` otherwise, for every other type too.
static func is_finite_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D:
			return value.is_finite()
		TYPE_COLOR:
			var color: Color = value
			return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)
	return true


## Returns `true` when no sample is held.
func is_empty() -> bool:
	return _samples.is_empty()


## Returns how many samples are held.
func size() -> int:
	return _samples.size()


## Returns the newest sample's stamp, or `-INF` when empty.
func latest_time() -> float:
	return _samples.back()[0] if not _samples.is_empty() else -INF


## Drops every sample.
func clear() -> void:
	_samples.clear()


static func _blend(from: Variant, to: Variant, weight: float) -> Variant:
	if typeof(from) != typeof(to):
		return from
	match typeof(from):
		TYPE_FLOAT, TYPE_INT:
			return lerpf(from, to, weight)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
			return from.lerp(to, weight)
		TYPE_QUATERNION:
			return _blend_quaternion(from, to, weight)
		TYPE_BASIS:
			return _blend_basis(from, to, weight)
		TYPE_TRANSFORM2D:
			if _is_collapsed_2d(from) or _is_collapsed_2d(to):
				return from
			return from.interpolate_with(to, weight)
		TYPE_TRANSFORM3D:
			if _is_collapsed(from.basis) or _is_collapsed(to.basis):
				return from
			return from.interpolate_with(to, weight)
	return from


## Rotation by the shorter arc between the two quaternions, each normalized first; a
## zero-length one, or one so long its squared length overflows, cannot be normalized,
## so the earlier value is held.
static func _blend_quaternion(from: Quaternion, to: Quaternion, weight: float) -> Quaternion:
	if not _can_normalize(from) or not _can_normalize(to):
		return from
	return from.normalized().slerp(to.normalized(), weight)


## Each basis split into a rotation and a per-axis scale: the rotations are slerped, the
## scales blended linearly. Shear is not kept (as `Transform3D.interpolate_with` does). A
## collapsed basis (see `_is_collapsed`) has no rotation to read, so the earlier value
## is held.
static func _blend_basis(from: Basis, to: Basis, weight: float) -> Basis:
	if _is_collapsed(from) or _is_collapsed(to):
		return from
	var rotation := from.get_rotation_quaternion().slerp(to.get_rotation_quaternion(), weight)
	return Basis(rotation) * Basis.from_scale(from.get_scale().lerp(to.get_scale(), weight))


## Whether `q` can be normalized: its squared length is neither zero nor overflowed.
static func _can_normalize(q: Quaternion) -> bool:
	var length_squared := q.length_squared()
	return length_squared != 0.0 and is_finite(length_squared)


## Whether `basis` has no rotation to read: an axis of zero length, axes lying in one
## plane, or axes so long their volume overflows a float. Judged relative to the axes'
## lengths, so a tiny but valid scale (a unit growing from 0.01) still blends.
static func _is_collapsed(basis: Basis) -> bool:
	var volume := basis.x.length() * basis.y.length() * basis.z.length()
	if volume == 0.0 or not is_finite(volume):
		return true
	var flatness := basis.determinant() / volume
	return not is_finite(flatness) or is_zero_approx(flatness)


## `_is_collapsed` for a 2D transform's two axes.
static func _is_collapsed_2d(transform: Transform2D) -> bool:
	var area := transform.x.length() * transform.y.length()
	if area == 0.0 or not is_finite(area):
		return true
	var flatness := transform.determinant() / area
	return not is_finite(flatness) or is_zero_approx(flatness)
