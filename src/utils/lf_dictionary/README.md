# LFDictionary

> Read, write and compare values buried inside dictionaries with a path like `"audio.music.volume"`.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_dictionary.gd` |
| **Tests** | `tests/test_lf_dictionary.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`deep_equal`), `LFLogger` |

## When to use it

Use it when your data is nested dictionaries (a settings file, a save game, a JSON reply)
and you want to reach a value deep inside without a chain of `if has(...)` checks:
`LFDictionary.get_by(settings, "audio.music.volume", 1.0)` returns the volume, or `1.0`
when any part of the path is missing. `get_by` also walks Object properties, so
`get_by(unit, "stats.armor", 0)` works on a node. `diff`/`apply_diff` send only what
changed in a state dictionary (a network update, an undo step). For a single top-level key,
Godot's own `Dictionary.get(key, default)` is enough. To load and save JSON files, see
`LFJson`.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

func _ready() -> void:
	# A Dictionary is a set of named values; here they are nested inside each other.
	var settings := {"audio": {"music": {"volume": 0.8}}}

	# Read the value at the path "audio.music.volume".
	# 1.0 is what you get back if any part of the path is missing.
	print(LFDictionary.get_by(settings, "audio.music.volume", 1.0))

	# This path does not exist, so the fallback comes back.
	print(LFDictionary.get_by(settings, "audio.sfx.volume", 1.0))

	# Write a value. Missing levels along the path are created for you.
	LFDictionary.set_by_path(settings, "audio.sfx.volume", 0.5)
	print(settings)
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. Look at the **Output** panel at the bottom of the editor. You should see `0.8`, then `1.0`, then the whole dictionary, which now has both `music` and `sfx` inside `audio`.
6. For your own game, change the dictionary and the path strings. Each dot in a path steps one level deeper; the last argument of `get_by` is the value to use when nothing is found.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `get_by` | `static get_by(source: Variant, path: String, default: Variant = null) -> Variant` | Walks Dictionaries (by key) and Objects (by property). Returns `default` as soon as a step is missing, is not a Dictionary or Object, or is a freed Object. Never reports an error. |
| `get_by_steps` | `static get_by_steps(source: Variant, steps: PackedStringArray, default: Variant = null) -> Variant` | `get_by` with the path already split, for a path read many times. Empty `steps` returns `source`. |
| `get_by_path` | `static get_by_path(dictionary: Dictionary, props_path: String, step_delta: int = 0) -> Variant` | Walks dictionary keys only; `null` when a step is missing. `step_delta` stops that many segments early (`1` returns the parent dictionary). A `step_delta` outside `0..segments` is reported and returns `null`. |
| `set_by_path` | `static set_by_path(dictionary: Dictionary, props_path: String, value: Variant) -> Dictionary` | Sets the last key to `value`, creating missing intermediate dictionaries and **overwriting** any intermediate that is not a Dictionary with `{}`. Changes `dictionary` in place and returns it. |
| `erase_by_path` | `static erase_by_path(dictionary: Dictionary, props_path: String) -> Dictionary` | Erases the last key; a no-op when a step is missing or is not a Dictionary (an Object included). Changes `dictionary` in place and returns it. |
| `diff` | `static diff(previous: Dictionary, next: Dictionary) -> Dictionary` | `{changed: {key: value}, removed: [key]}`, one level deep. A key is changed when it is new or its value is not `LFUtils.deep_equal` to the old one; a changed value is sent whole. Inputs untouched. |
| `apply_diff` | `static apply_diff(base: Dictionary, delta: Dictionary) -> Dictionary` | A shallow copy of `base` with `changed` set and `removed` erased. `base` is never modified; a missing part counts as empty. |
| `KEY_CHANGED` | `const KEY_CHANGED := 'changed'` | The key of a `diff` result holding `{key: new value}`; `apply_diff` reads it. |
| `KEY_REMOVED` | `const KEY_REMOVED := 'removed'` | The key of a `diff` result holding the removed keys; `apply_diff` reads it. |
| `invert` | `static invert(d: Dictionary) -> Dictionary` | `{value: key}`; when values repeat, the later key wins. `d` is not modified. Values become keys: Godot hashes them, and prints "Max recursion reached" for a value nested about 100 levels deep or more. |
| `lower_median_by_key` | `static lower_median_by_key(dicts: Array) -> Dictionary` | Per key, the lower median of its values across `dicts` (missing counts as 0, values cut to int); keys with a median of 0 or less are left out. |

## Usage

```gdscript
extends Node

func _ready() -> void:
	var settings := {"audio": {"music": {"volume": 0.8}}}

	# Read deep values, with a fallback when the path is missing.
	print(LFDictionary.get_by(settings, "audio.music.volume", 1.0))  # 0.8
	print(LFDictionary.get_by(settings, "audio.sfx.volume", 1.0))    # 1.0 (missing)
	print(LFDictionary.get_by_path(settings, "audio.music.volume", 1))  # {"volume": 0.8}

	# Write and erase (missing dictionaries along the way are created).
	LFDictionary.set_by_path(settings, "audio.sfx.volume", 0.5)
	LFDictionary.erase_by_path(settings, "audio.music")

	# Send only what changed, and rebuild it on the other side.
	var last_sent := {"hp": 10, "gold": 5}
	var current := {"hp": 7, "gold": 5}
	var delta := LFDictionary.diff(last_sent, current)  # {changed: {hp: 7}, removed: []}
	var rebuilt := LFDictionary.apply_diff(last_sent, delta)
	print(rebuilt)  # {"hp": 7, "gold": 5}

	# Swap keys and values.
	var name_of := LFDictionary.invert({"move": 1, "attack": 2})  # {1: "move", 2: "attack"}
	print(name_of[2])  # attack
```

## Notes

- Segments are always string keys; no array indices.
- `set_by_path` replaces a non-Dictionary intermediate: `set_by_path({a = 5}, 'a.b', 1)`
  gives `{a = {b = 1}}`, and the `5` is gone.
- `set_by_path` and `erase_by_path` change the input. Duplicate it first if you need the
  original (as `LFJsonFileObserver` does).
- `get_by_path`/`set_by_path`/`erase_by_path` walk dictionary keys only. `get_by` also walks
  Object properties.
- `diff` and `apply_diff` share values rather than copying them: treat the values as
  read-only (replace a value whole instead of editing it), or a later edit shows up on both
  sides.
- After a JSON round trip (the diff is turned into JSON text and read back), keys come back as Strings and numbers as
  floats; `diff` compares values deeply (`LFUtils.deep_equal`), so `1` and `1.0` count as equal.
- `diff` compares values as deep as `LFUtils.deep_equal` is exact (100 nested Arrays/Dictionaries); comparing values nested more than about 50 deep prints the engine's "Max recursion reached" log lines (see `LFUtils.deep_equal`).
- A NaN field that stays NaN is not reported as changed (`deep_equal` treats NaN as equal
  to NaN, also inside arrays, vectors and colors).
- `diff` compares each pair of values of one type with the engine's `==` first and runs
  `deep_equal` only on the pairs it reports different (a changed value, a NaN, an int
  against a float) or, for an Array or Dictionary, whose `hash()` differs. Measured once, on an Apple-silicon Mac: a 500-entry snapshot of small per-unit
  dictionaries, 10% changed, diffs in about 0.4 ms.
