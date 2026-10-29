## Changes one property of an object from a data entry: add to it, multiply it or set it.
##
## The entry is a Dictionary: `path` (a property, or a dotted path to one on a nested
## object), `value`, and optionally `op`, `clampMax` and `alsoSetCurrentField`. Static: call
## it on the class, never `.new()` it.
class_name LFPropertyPatch
extends RefCounted

## Entry key: the dotted path of the property to change.
const KEY_PATH := "path"
## Entry key: the operand.
const KEY_VALUE := "value"
## Entry key (optional): `add` (the default), `multiply` or `set`; anything else changes nothing.
const KEY_OP := "op"
## Entry key (optional): the result is capped at this value.
const KEY_CLAMP_MAX := "clampMax"
## Entry key (optional): a property of the same object that is set to the new value too.
const KEY_ALSO_SET := "alsoSetCurrentField"
## `op` that adds `value`.
const OP_ADD := "add"
## `op` that multiplies by `value`.
const OP_MULTIPLY := "multiply"
## `op` that replaces the property with `value`.
const OP_SET := "set"

static var _log := LFLogger.new()


## Applies `modifier` to `root`. The path is read with `LFDictionary.get_by`; the last step
## is the property, and an int property stays an int. Returns false, with an error, when the
## entry lacks `path` or `value`, the path does not reach an object, or the object has no such property. Assigns through `set`, so a setter on the property runs.
static func apply(root: Object, modifier: Dictionary) -> bool:
	if not modifier.has(KEY_PATH) or not modifier.has(KEY_VALUE):
		_log.error('LFPropertyPatch: the entry needs "%s" and "%s"' % [KEY_PATH, KEY_VALUE])
		return false
	var path := String(modifier[KEY_PATH])
	var parent_path := path.get_basename()
	var target: Variant = root if parent_path == path else LFDictionary.get_by(root, parent_path)
	if not target is Object:
		_log.error('LFPropertyPatch: path "%s" does not reach an object' % path)
		return false
	var prop := path.get_extension() if parent_path != path else path
	if not prop in target:
		_log.error('LFPropertyPatch: no property "%s" at path "%s"' % [prop, path])
		return false
	var current: Variant = target.get(prop)
	var is_int := current is int
	var value: Variant = modifier[KEY_VALUE]

	var new_value: Variant
	match modifier.get(KEY_OP, OP_ADD):
		OP_ADD:
			new_value = current + value
		OP_MULTIPLY:
			new_value = current * value
		OP_SET:
			new_value = value
		_:
			new_value = current

	if modifier.has(KEY_CLAMP_MAX):
		new_value = minf(new_value, modifier[KEY_CLAMP_MAX])

	target.set(prop, int(new_value) if is_int else new_value)
	if modifier.has(KEY_ALSO_SET):
		target.set(String(modifier[KEY_ALSO_SET]), target.get(prop))
	return true
