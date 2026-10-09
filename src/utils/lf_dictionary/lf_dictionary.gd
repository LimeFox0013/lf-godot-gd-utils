## Reads, writes and compares nested dictionaries using paths like `"audio.music.volume"`.
##
## Every method is static: call it on the class (`LFDictionary.get_by(...)`), never create
## an instance. It can get, set and erase a value deep inside nested dictionaries by a
## dot-separated path (`get_by` also reads Object properties), compute what changed between
## two dictionaries and apply that change, and swap keys with values.
class_name LFDictionary

## The key of `diff()`'s result holding `{key: new value}` for every new or changed key;
## `apply_diff()` reads it back.
const KEY_CHANGED := 'changed'
## The key of `diff()`'s result holding the Array of keys that were removed; `apply_diff()`
## reads it back.
const KEY_REMOVED := 'removed'

## Separates the steps of a path (`"a.b.c"`).
const _PATH_SEPARATOR := '.'

static var _log := LFLogger.new()


## The value at dot-separated `path` inside `source`, walking Dictionaries (by key) and
## Objects (by property): `get_by(node, "size.width")`. Returns `default` as soon as a step
## is missing, is not a Dictionary or Object, or is a freed Object — never an error.
static func get_by(source: Variant, path: String, default: Variant = null) -> Variant:
	return get_by_steps(source, path.split(_PATH_SEPARATOR), default)


## `get_by` with the path already split — for a path read many times. An empty `steps`
## returns `source` itself.
static func get_by_steps(source: Variant, steps: PackedStringArray, default: Variant = null) -> Variant:
	return _walk(source, steps, steps.size(), default, true)


## The value at a dot-delimited `props_path` (dictionary keys only), or `null` as soon as a
## step is missing. `step_delta` stops that many segments short of the end (`1` returns the
## dictionary that holds the last key). A `step_delta` outside `0..segment count` reports an
## error and returns `null`.
static func get_by_path(dictionary: Dictionary, props_path: String, step_delta: int = 0) -> Variant:
	var path_arr := props_path.split(_PATH_SEPARATOR)
	if step_delta < 0 or step_delta > path_arr.size():
		_log.error('LFDictionary.get_by_path: step_delta %d is outside 0..%d' % [step_delta, path_arr.size()])
		return null
	# Segments are dictionary keys here, never object properties.
	return _walk(dictionary, path_arr, path_arr.size() - step_delta, null, false)


## Follows the first `count` of `steps` from `source`; `default` as soon as a step is
## missing or not walkable. Objects are walked by property only when `objects` is true.
static func _walk(source: Variant, steps: PackedStringArray, count: int, default: Variant, objects: bool) -> Variant:
	var value: Variant = source
	for i in count:
		var step := steps[i]
		match typeof(value):
			TYPE_DICTIONARY:
				if not value.has(step):
					return default
				value = value[step]
			TYPE_OBJECT:
				if not objects or not is_instance_valid(value) or not step in value:
					return default
				value = value.get(step)
			_:
				return default
	return value


## Sets the value at `props_path`, creating any missing intermediate dictionaries. An
## intermediate that exists but is not a Dictionary (a number, a String, an Array...) is
## overwritten by a new empty Dictionary — its old value is lost. Changes `dictionary` in
## place and returns it.
static func set_by_path(dictionary: Dictionary, props_path: String, value: Variant) -> Dictionary:
	var path_arr := props_path.split(_PATH_SEPARATOR)
	var target: Dictionary = dictionary
	for i in path_arr.size() - 1:
		var next: Variant = target.get(path_arr[i])
		if not (next is Dictionary):
			next = {}
			target.set(path_arr[i], next)
		target = next
	target.set(path_arr[path_arr.size() - 1], value)
	return dictionary


## Erases the value at `props_path`; a no-op when any step of the path is missing. Changes
## `dictionary` in place and returns it.
static func erase_by_path(dictionary: Dictionary, props_path: String) -> Dictionary:
	var path_arr := props_path.split(_PATH_SEPARATOR)
	var target_prop := path_arr[path_arr.size() - 1]
	var target: Variant = get_by_path(dictionary, props_path, 1)
	if target is Dictionary:
		target.erase(target_prop)
	return dictionary


## What changed from `previous` to `next`, one level deep: `{changed: {key: value},
## removed: [key, ...]}`. A key is changed when it is new in `next` or its value is not
## `LFUtils.deep_equal` to the old one (a NaN that stays NaN is unchanged; a changed value
## is sent whole, never diffed inside); a key of `previous` that `next` lacks is removed.
## Neither input is modified, and the values in `changed` are `next`'s own (not copies).
## A value is compared as deep as [method LFUtils.deep_equal] is exact (100 levels).
static func diff(previous: Dictionary, next: Dictionary) -> Dictionary:
	var changed := {}
	for key: Variant in next:
		var value: Variant = next[key]
		if not previous.has(key):
			changed[key] = value
			continue
		var old: Variant = previous[key]
		# The engine's == first (only between values of one type: across types it can be a
		# script error); when it says equal so does deep_equal, which then runs only for
		# the values it reports different. For an Array or Dictionary the equal hash is
		# checked too, because the engine's == stops looking after about 51 nested levels.
		if typeof(old) == typeof(value) and old == value and (typeof(old) != TYPE_ARRAY and typeof(old) != TYPE_DICTIONARY or hash(old) == hash(value)):
			continue
		if not LFUtils.deep_equal(old, value):
			changed[key] = value
	var removed := []
	for key: Variant in previous:
		if not next.has(key):
			removed.append(key)
	return {KEY_CHANGED: changed, KEY_REMOVED: removed}


## `base` with a `diff()` result applied: a shallow copy of `base`, every `changed` key
## set and every `removed` key erased. `base` is never modified. Missing `changed` or
## `removed` entries count as empty, so a diff that went through JSON still applies.
static func apply_diff(base: Dictionary, delta: Dictionary) -> Dictionary:
	var result := base.duplicate()
	var changed: Variant = delta.get(KEY_CHANGED, {})
	if changed is Dictionary:
		result.merge(changed, true)
	var removed: Variant = delta.get(KEY_REMOVED, [])
	if removed is Array:
		for key: Variant in removed:
			result.erase(key)
	return result


## `{value: key}` for every entry of `d`. When several keys share a value, the later key
## (in `d`'s order) wins. `d` is not modified. Values become keys, so Godot hashes them: a
## value that is an Array or Dictionary nested about 100 levels deep or more makes the
## engine print "Max recursion reached" while hashing it.
static func invert(d: Dictionary) -> Dictionary:
	var inverted := {}
	for key: Variant in d:
		inverted[d[key]] = key
	return inverted
