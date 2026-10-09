## Builds and reads the tool definitions you offer a language model (an "LLM", such as
## Claude or a GPT model).
##
## A tool is an action the model may choose, described as `{name, description,
## parameters}` where `parameters` is a closed JSON-schema object (JSON schema: a standard
## way to describe what fields an object has and their types). This is the provider-neutral
## form `LFLlmProvider` takes. `define` builds one, `find_tool` looks one up by name, and `coerce_args` turns a model's
## call input into clean arguments: only the schema's own keys, each cast to its type.
class_name LFLlmTool
extends RefCounted

static var _log := LFLogger.new(['LFLlmTool:'])

## Schema key naming a value's type.
const _KEY_TYPE := 'type'
## Schema type of the parameters object.
const _TYPE_OBJECT := 'object'
## Schema key mapping argument names to their schemas.
const _KEY_PROPERTIES := 'properties'
## Schema key listing the required argument names.
const _KEY_REQUIRED := 'required'
## Schema key that closes the object to undeclared keys.
const _KEY_ADDITIONAL_PROPERTIES := 'additionalProperties'
## Schema type cast to int.
const _TYPE_INTEGER := 'integer'
## Schema type cast to float.
const _TYPE_NUMBER := 'number'
## Schema type cast to String.
const _TYPE_STRING := 'string'
## Schema type cast to bool.
const _TYPE_BOOLEAN := 'boolean'
## Text read as `true` (lower-cased).
const _TRUE_TEXT := 'true'
## Text read as `false` (lower-cased).
const _FALSE_TEXT := 'false'
## 2^63: a float at or above it, or below its negation, does not fit a 64-bit int.
const _INT64_LIMIT := 9223372036854775808.0
## Schema key listing the only values an argument may take.
const _KEY_ENUM := 'enum'
## Schema key for the lowest number an argument may be.
const _KEY_MINIMUM := 'minimum'
## Schema key for the highest number an argument may be.
const _KEY_MAXIMUM := 'maximum'
## Schema key for the most characters a string argument may have.
const _KEY_MAX_LENGTH := 'maxLength'
## Most characters of a rejected value quoted in a warning.
const _SHOWN_LENGTH := 60
## Exponent marker of a numeric string (lower-cased).
const _EXPONENT_MARK := 'e'
## Largest exponent magnitude parsed; no finite double needs more.
const _MAX_EXPONENT := 300


## Returns a tool named `name` whose `parameters` is a closed object schema (the model may
## send only these keys): `properties` maps each argument name to its schema, such as
## `{'x': {'type': 'integer'}}`. The result holds `properties` (deep-copied), the
## `required` names (copied) and `additionalProperties: false`.
static func define(name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary:
	return {
		LFLlmProvider.KEY_NAME: name,
		LFLlmProvider.KEY_DESCRIPTION: description,
		LFLlmProvider.KEY_PARAMETERS: {
			_KEY_TYPE: _TYPE_OBJECT,
			_KEY_PROPERTIES: properties.duplicate(true),
			_KEY_REQUIRED: required.duplicate(),
			_KEY_ADDITIONAL_PROPERTIES: false,
		},
	}


## Returns the tool in `tools` named `name`, or `{}` when there is none. Entries that are
## not Dictionaries, or whose `name` is not a String, are skipped.
static func find_tool(tools: Array, name: String) -> Dictionary:
	for tool: Variant in tools:
		if not tool is Dictionary:
			continue
		var tool_name: Variant = tool.get(LFLlmProvider.KEY_NAME)
		if tool_name is String and tool_name == name:
			return tool
	return {}


## Returns `true` when `tool` has the neutral shape a provider builds requests from: a
## Dictionary with a non-empty String `name`, a String `description` and a Dictionary
## `parameters`. Only the shape is checked, not whether `parameters` is a valid JSON schema.
static func is_valid_tool(tool: Variant) -> bool:
	if not tool is Dictionary:
		return false
	var name: Variant = tool.get(LFLlmProvider.KEY_NAME)
	return name is String and name != '' \
			and tool.get(LFLlmProvider.KEY_DESCRIPTION) is String \
			and tool.get(LFLlmProvider.KEY_PARAMETERS) is Dictionary


## Returns the entries of `input` that `properties` (a schema's `properties`) declares, minus the
## keys in `skip`, each cast to its schema `type`: `integer` → int, `number` → float,
## `string` → String, `boolean` → bool; any other type is kept as is. A null, or a value
## that cannot be read as its type (an Array for an integer, a non-numeric string for a
## number, a number or numeric string with a fraction for an integer — `4.0` is 4, `2.9`
## is left out —, an infinite or NaN number, a numeric string with an exponent beyond
## ±300, an integer beyond the 64-bit range), is left out. Keys `properties` does not declare are always left out.
##
## The schema's `enum` (the cast value must equal one of the listed values), `minimum` and
## `maximum` (numbers; inclusive) and `maxLength` (strings; characters) are enforced after
## the cast: an argument that breaks one is rejected, not clamped. It is left out like an
## uncastable value, and a pushed warning names the argument and the rule it broke, so a
## caller can tell "the model sent nothing" from "the model sent a value outside the
## schema". `minLength`, `pattern`, `exclusiveMinimum`, `exclusiveMaximum` and the other
## schema keywords are not checked.
static func coerce_args(properties: Dictionary, input: Dictionary, skip: Array = []) -> Dictionary:
	var args := {}
	for key: Variant in properties:
		if key in skip or not input.has(key):
			continue
		var schema: Variant = properties[key]
		var type: Variant = schema.get(_KEY_TYPE) if schema is Dictionary else null
		var value: Variant = _cast(input[key], type)
		if value == null:
			continue
		var broken := _broken_rule(value, schema) if schema is Dictionary else ''
		if broken != '':
			_log.warning('argument "%s" rejected: %s' % [key, broken])
			continue
		args[key] = value
	return args


## Why `value` breaks the `enum`, `minimum`, `maximum` or `maxLength` of `schema`, or ''.
static func _broken_rule(value: Variant, schema: Dictionary) -> String:
	var allowed: Variant = schema.get(_KEY_ENUM)
	if allowed is Array and not _in_enum(value, allowed):
		return '%s is not one of %s' % [_shown(value), _shown(allowed)]
	if value is int or value is float:
		var lowest: Variant = schema.get(_KEY_MINIMUM)
		if (lowest is int or lowest is float) and value < lowest:
			return '%s is below the minimum %s' % [_shown(value), lowest]
		var highest: Variant = schema.get(_KEY_MAXIMUM)
		if (highest is int or highest is float) and value > highest:
			return '%s is above the maximum %s' % [_shown(value), highest]
	var longest: Variant = schema.get(_KEY_MAX_LENGTH)
	if value is String and (longest is int or longest is float) and value.length() > longest:
		return 'text of %d characters is longer than maxLength %s' % [value.length(), longest]
	return ''


## Whether `value` equals an entry of `allowed` (a number equals a number of the same value;
## otherwise the types must match too, so `1` is not `"1"` or `true`).
static func _in_enum(value: Variant, allowed: Array) -> bool:
	for each: Variant in allowed:
		var both_numbers: bool = (value is int or value is float) and (each is int or each is float)
		if both_numbers and value == each:
			return true
		if typeof(value) == typeof(each) and value == each:
			return true
	return false


static func _shown(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= _SHOWN_LENGTH else text.left(_SHOWN_LENGTH) + '...'


static func _cast(value: Variant, type: Variant) -> Variant:
	if value == null:
		return null
	match type:
		_TYPE_INTEGER:
			var number: Variant = _number(value)
			if number == null:
				return null
			if number is float and (number >= _INT64_LIMIT or number < -_INT64_LIMIT):
				return null
			# 2.9 is not an integer; truncating it would act on a value the model never sent.
			if number is float and number != floorf(number):
				return null
			return int(number)
		_TYPE_NUMBER:
			var number: Variant = _number(value)
			if number == null:
				return null
			return float(number)
		_TYPE_STRING:
			return str(value)
		_TYPE_BOOLEAN:
			if value is bool:
				return value
			if value is float and not is_finite(value):
				return null
			if value is int or value is float:
				return value != 0
			if value is String and value.to_lower() in [_TRUE_TEXT, _FALSE_TEXT]:
				return value.to_lower() == _TRUE_TEXT
			return null
	return value


static func _number(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		if not is_finite(value):
			return null
		return value
	if value is bool:
		return int(value)
	if value is String and value.strip_edges().is_valid_float():
		var text: String = value.strip_edges().to_lower()
		# A huge exponent makes `to_float` raise an engine error; no finite double has one.
		if text.contains(_EXPONENT_MARK) and _exponent_too_large(text.get_slice(_EXPONENT_MARK, 1)):
			return null
		var parsed := text.to_float()
		if not is_finite(parsed):
			return null
		return parsed
	return null


## Whether the exponent digits `exponent` (after the `e`, maybe signed) are beyond ±300.
## Read by digit count first: `to_int` itself raises an engine error on a number beyond
## the 64-bit range.
static func _exponent_too_large(exponent: String) -> bool:
	var digits := exponent.trim_prefix('+').trim_prefix('-').lstrip('0')
	if digits.length() > str(_MAX_EXPONENT).length():
		return true
	return digits.to_int() > _MAX_EXPONENT
