# LFSettingDefinition

> Describes one options-menu setting and always turns whatever it is given into a legal value.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `LFSettingDefinition.choice(...)` or `LFSettingDefinition.integer(...)` |
| **Files** | `lf_setting_definition.gd` |
| **Tests** | `tests/test_lf_setting_definition.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils`, `LFLogger` |

## When to use it

Use it when a screen shows settings (a pick-one list, or a number in steps) and the values
come from players, saved files or the network, so they can be missing or wrong. One
definition per setting says what is legal; your screen draws a row for each and never
names a particular setting.

## Step by step

1. Make a scene with one **Node** and attach a script to it (right-click, **Attach Script**, *Create*).
2. Replace the script with:

```gdscript
extends Node

func _ready() -> void:
	var time := LFSettingDefinition.integer("time", "Round time", "Seconds per round.", 30, 600, 30, 60, func(v): return "%d s" % int(v))
	print(time.sanitize(100))   # 90
	print(time.sanitize("x"))   # 60
	print(time.display(90))     # 90 s
```

3. Press **F6**. The Output panel shows `90`, `60` and `90 s`.

## API

| Member | Signature | Description |
|---|---|---|
| `Kind` | `enum Kind { CHOICE, INTEGER }` | Pick-one or whole number. |
| `choice` | `static choice(setting_id, setting_label, setting_description, choices, initial) -> LFSettingDefinition` | A pick-one setting; `choices` is `[{ "value", "label" }]`. |
| `integer` | `static integer(setting_id, setting_label, setting_description, lowest, highest, increment, initial, formatter := Callable()) -> LFSettingDefinition` | A whole number from `lowest` to `highest` in steps of `increment`. |
| `id` / `label` / `description` / `kind` / `default_value` | `var` | What the setting is called, explained as, and falls back to. |
| `options` | `var options: Array` | CHOICE only. |
| `min_value` / `max_value` / `step` / `format_fn` | `var` | INTEGER only; `format_fn.call(value) -> String` shapes the text. |
| `sanitize` | `sanitize(value: Variant) -> Variant` | A legal value: unknown choice or non-number becomes the default; an integer is cut to a whole number, snapped to a step, clamped. |
| `display` | `display(value: Variant) -> String` | A choice's label (the value itself if unknown), or the integer through `format_fn`. |
| `values` | `values() -> Array` | Every legal value in order. |

## Usage

```gdscript
settings[definition.id] = definition.sanitize(loaded.get(definition.id))
picker_items = definition.values()
```

## Notes

- A float is cut to a whole number first (52.9 counts as 52), then snapped to the nearest step.
- A `step` of 0 or less counts as 1 in `sanitize` and `values` (a warning is logged once, when `integer(...)` builds the definition); the `step` variable itself is left as given.
- A float beyond the range is clamped to it before being cut to a whole number, so a huge float gives `min_value` or `max_value` (a warning is logged on each such call, for floats beyond about 9e18 or infinite). NaN gives the default, with a warning.
- Choices are matched with `LFUtils.find_by`, so a choice value must be comparable with `==`.
