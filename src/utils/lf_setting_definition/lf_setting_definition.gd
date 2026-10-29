## Describes one option-menu setting: its id, label, kind (a pick-one list or a whole
## number in a range) and default. Cleans up any value a player or a file hands you.
##
## A settings screen can draw one row per definition and never name a particular setting.
## `sanitize(value)` always returns a legal value; `display(value)` is the text to show.
class_name LFSettingDefinition
extends RefCounted

enum Kind { CHOICE, INTEGER }

## Floats larger than this (or infinite) are warned about before being clamped.
const _MAX_SAFE_FLOAT := 9.0e18

## Identifies the setting in saved data.
var id: String
## The name the player sees.
var label: String
## A sentence explaining the setting, for a tooltip.
var description: String
## `Kind.CHOICE` or `Kind.INTEGER`.
var kind: int
## The value used when none is set or a given one is not legal.
var default_value: Variant
## CHOICE only: `[{ "value": Variant, "label": String }]`.
var options: Array = []
## INTEGER only: the smallest legal value.
var min_value := 0
## INTEGER only: the largest legal value.
var max_value := 0
## INTEGER only: legal values are `min_value` plus a whole number of steps. A value below 1 counts as 1.
var step := 1
## INTEGER only: `format_fn.call(value) -> String`, how a value reads (0 as "Unlimited"). Empty shows the number.
var format_fn: Callable = Callable()

var _log := LFLogger.new(['LFSettingDefinition'])


## A pick-one setting; `choices` is `[{ "value", "label" }]`.
static func choice(setting_id: String, setting_label: String, setting_description: String, choices: Array, initial: Variant) -> LFSettingDefinition:
	var definition := LFSettingDefinition.new()
	definition.id = setting_id
	definition.label = setting_label
	definition.description = setting_description
	definition.kind = Kind.CHOICE
	definition.options = choices
	definition.default_value = initial
	return definition


## A whole-number setting from `lowest` to `highest` in steps of `increment`.
static func integer(setting_id: String, setting_label: String, setting_description: String, lowest: int, highest: int, increment: int, initial: int, formatter := Callable()) -> LFSettingDefinition:
	var definition := LFSettingDefinition.new()
	definition.id = setting_id
	definition.label = setting_label
	definition.description = setting_description
	definition.kind = Kind.INTEGER
	definition.min_value = lowest
	definition.max_value = highest
	definition.step = increment
	if increment < 1:
		definition._log.warning(setting_id, 'step must be at least 1, got', increment, '- using 1')
	definition.default_value = initial
	definition.format_fn = formatter
	return definition


## `value` made legal: an unknown choice or a non-number becomes the default; an integer
## is cut to a whole number, snapped to the nearest step and clamped to the range.
func sanitize(value: Variant) -> Variant:
	if kind == Kind.CHOICE:
		return value if LFUtils.find_by(options, "value", value) != null else default_value
	if not (value is int or value is float):
		return default_value
	if value is float:
		if is_nan(value):
			_log.warning(id, 'got NaN, using the default', default_value)
			return default_value
		if absf(value) > _MAX_SAFE_FLOAT:
			_log.warning(id, 'got a float beyond the whole-number range,', value, '- clamping it')
		# Clamp first: int() of a float beyond the int range is undefined.
		value = clampf(value, float(min_value), float(max_value))
	var safe_step := _safe_step()
	var snapped_value := min_value + int(round(float(int(value) - min_value) / safe_step)) * safe_step
	return clampi(snapped_value, min_value, max_value)


## How `value` reads on screen: a choice's label (the value itself if unknown), or the integer through `format_fn`.
func display(value: Variant) -> String:
	if kind == Kind.CHOICE:
		var option: Variant = LFUtils.find_by(options, "value", value)
		return option["label"] if option != null else str(value)
	return format_fn.call(value) if format_fn.is_valid() else str(value)


## Every legal value in order: the choices' values, or the integer range in steps.
func values() -> Array:
	if kind == Kind.CHOICE:
		return options.map(func(option): return option["value"])
	return range(min_value, max_value + 1, _safe_step())


## `step`, or 1 when it is 0 or negative.
func _safe_step() -> int:
	return step if step > 0 else 1
