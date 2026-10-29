# LFPropertyPatch

> Change one property of an object from a data entry: add to it, multiply it or set it, by a dotted path, with an optional cap.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_property_patch.gd` |
| **Tests** | `tests/test_lf_property_patch.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFDictionary`, `LFLogger` |

## When to use it

Use it when upgrades, perks or cheats are written as data ("+20 max health", "x1.5
damage") and you want to apply them to a live object without a line of code per upgrade.
For per-owner upgrade levels that add up to a stat, use `LFModifierLevels` or
`LFLayeredStats` instead; this changes the object's own property directly.

## Step by step

1. Choose *Scene → New Scene*, add a **Node** as the root, press *Attach Script* and replace the script with:

   ```gdscript
   extends Node

   var damage := 10
   var speed := 2.5


   func _ready() -> void:
   	LFPropertyPatch.apply(self, {"path": "damage", "op": "multiply", "value": 1.5})
   	LFPropertyPatch.apply(self, {"path": "speed", "value": 1.0, "clampMax": 3.0})
   	print(damage, " ", speed)
   ```
2. Press **F6** and save the scene. The *Output* panel shows `15 3.0`: damage went from 10 to 15, and speed from `2.5 + 1.0 = 3.5` was capped at 3.0.

## API

| Member | Signature | Description |
|---|---|---|
| `apply` | `static apply(root: Object, modifier: Dictionary) -> bool` | Applies the entry to `root`. False, with an error, and nothing changed, when the entry lacks `path` or `value`, the path does not reach an object, or that object has no such property. |
| `KEY_PATH`, `KEY_VALUE` | `const String` (`path`, `value`) | Required entry keys. `path` is a property or a dotted path to one on a nested object. |
| `KEY_OP` | `const String` (`op`) | `OP_ADD` (default), `OP_MULTIPLY` or `OP_SET`; any other value changes nothing. |
| `KEY_CLAMP_MAX` | `const String` (`clampMax`) | Caps the result. |
| `KEY_ALSO_SET` | `const String` (`alsoSetCurrentField`) | A property of the same object that also gets the new value (raising a maximum tops up the current value). |

## Usage

```gdscript
var unit := make_unit()   # has `damage` and a nested `health` object with `max` and `current`
LFPropertyPatch.apply(unit, {"path": "damage", "op": "multiply", "value": 1.5})
LFPropertyPatch.apply(unit, {"path": "health.max", "value": 20, "alsoSetCurrentField": "current"})
```

## Notes

- An int property stays an int: the result is truncated.
- The value is written with `set`, so a setter on the property runs.
- `alsoSetCurrentField` names a property of the object that holds the patched one, not a path.
