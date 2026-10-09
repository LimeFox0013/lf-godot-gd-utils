## Parses JSON text without engine errors and stores vectors in JSON as plain number arrays.
##
## Every method is static: call it on the class, never create an instance. `parse` makes
## the engine log no error on invalid input (`JSON.parse_string` does), so untrusted
## text — a network message, a hand-edited file — can be read without error output. `vec2`/`vec3`
## turn vectors into plain number arrays and `to_vec2`/`to_vec3` read them back, rejecting
## anything that is not exactly the right count of finite numbers (no NaN, no infinity).
class_name LFJson
extends RefCounted

## How many numbers encode a Vector3.
const _VEC3_SIZE := 3
## How many numbers encode a Vector2.
const _VEC2_SIZE := 2

## The value `text` encodes, or `default` when it is not valid JSON. Logs nothing for
## invalid JSON. (A number too large for a float, such as `1e999`, is valid JSON: Godot
## reads it as `inf` and prints its own "Exponent too high" warning.)
## Numbers come back as floats, as Godot's JSON parser returns them.
static func parse(text: String, default: Variant = null) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return default
	return json.data


## The Dictionary `text` encodes, or null when it is not valid JSON or not an object.
## Logs nothing for invalid JSON (see `parse`).
static func parse_object(text: String) -> Variant:
	var value: Variant = parse(text)
	return value if value is Dictionary else null


## `[x, y, z]` for a Vector3 or Vector3i. It reads `v.x`, `v.y`, `v.z`, so a value
## without them is a script error, and one with them (a Vector4, a Dictionary with those
## keys) is read as well.
static func vec3(v: Variant) -> Array:
	return [v.x, v.y, v.z]


## `[x, y]` for a Vector2 or Vector2i. It reads `v.x`, `v.y`, so a value without them is
## a script error, and one with them is read as well.
static func vec2(v: Variant) -> Array:
	return [v.x, v.y]


## The Vector3 `raw` encodes, or `fallback` unless `raw` is an Array (or packed numeric
## array) of exactly three finite numbers that also fit a vector (a number too big for its
## 32-bit float, like `1e39`, is refused rather than becoming infinite).
static func to_vec3(raw: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not _is_numbers(raw, _VEC3_SIZE):
		return fallback
	var v := Vector3(raw[0], raw[1], raw[2])
	return v if v.is_finite() else fallback


## The Vector2 `raw` encodes, or `fallback` unless `raw` is an Array (or packed numeric
## array) of exactly two finite numbers that also fit a vector (see `to_vec3`).
static func to_vec2(raw: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if not _is_numbers(raw, _VEC2_SIZE):
		return fallback
	var v := Vector2(raw[0], raw[1])
	return v if v.is_finite() else fallback


const _ARRAY_TYPES := [
	TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
]


## Whether `raw` is an array of exactly `count` finite ints or floats (never bools).
static func _is_numbers(raw: Variant, count: int) -> bool:
	if not typeof(raw) in _ARRAY_TYPES or raw.size() != count:
		return false
	for each: Variant in raw:
		match typeof(each):
			TYPE_INT:
				pass
			TYPE_FLOAT:
				if not is_finite(each):
					return false
			_:
				return false
	return true
