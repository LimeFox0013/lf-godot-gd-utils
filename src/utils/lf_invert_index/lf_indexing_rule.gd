## One way an `LFInvertIndex` files its items: by the value found at a path inside each item.
##
## The path is dot-separated (`"meta.kind"`) and walks Dictionaries and Objects (read with
## `LFDictionary.get_by_steps`). The value found there is taken whole or spread over its array
## elements, dictionary keys or dictionary values (see `Target`).
class_name LFIndexingRule
extends RefCounted

## Separates the steps of `path`.
const _PATH_SEPARATOR := "."


## How the value found at `path` becomes the values an item is filed under.
enum Target {
	## The value itself.
	VALUE,
	## Each element of an Array (or packed array).
	ARRAY,
	## Each key of a Dictionary.
	DICTIONARY_KEYS,
	## Each value of a Dictionary.
	DICTIONARY_VALUES,
}

## What the rule indexes; lookups name the rule by it. Defaults to the path.
var name: String
## The dot-separated path read inside each item.
var path: String
## How the value at `path` is turned into index values.
var target: Target = Target.VALUE
var _steps: PackedStringArray


## A rule reading `property_path`, spread by `rule_target`, named `rule_name` (default: the
## path).
func _init(property_path: String, rule_target: Target = Target.VALUE, rule_name: String = "") -> void:
	path = property_path
	target = rule_target
	name = rule_name if rule_name != "" else property_path
	_steps = property_path.split(_PATH_SEPARATOR)


## The values `item` is indexed under. A missing path, or a value of the wrong shape for
## the target (a String under ARRAY, say), indexes nothing (an empty Array).
func values_of(item: Variant) -> Array:
	var value: Variant = LFDictionary.get_by_steps(item, _steps)
	if value == null:
		return []
	match target:
		Target.VALUE:
			return [value]
		Target.ARRAY:
			return Array(value) if _is_array(value) else []
		Target.DICTIONARY_KEYS:
			return value.keys() if value is Dictionary else []
		Target.DICTIONARY_VALUES:
			return value.values() if value is Dictionary else []
	return [] # a `target` set to an int outside the enum


static func _is_array(value: Variant) -> bool:
	var type := typeof(value)
	return type == TYPE_ARRAY or (type >= TYPE_PACKED_BYTE_ARRAY and type <= TYPE_PACKED_VECTOR4_ARRAY)
