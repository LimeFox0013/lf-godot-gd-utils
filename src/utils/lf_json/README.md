# LFJson

> Parses JSON text without logging an error when it is invalid, and stores vectors as plain number lists.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_json.gd` |
| **Tests** | `tests/test_lf_json.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it whenever you read JSON you did not write yourself: a message from a server, a save
file a player may have edited, a mod's config. Godot's `JSON.parse_string` prints a red
engine error on bad text; `LFJson.parse` returns your default without logging, so you
decide what to do. JSON has no vector type, so `vec3`/`to_vec3` store a position as
`[x, y, z]` and read it back, returning your fallback for anything malformed, so a bad
message can't become a NaN or infinite position (as long as your fallback is finite). To load and save JSON files on disk, use `LFFile.load_json`/`LFFile.save_json`;
to keep a JSON file in sync with a dictionary, use `LFJsonFileObserver`.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

func _ready() -> void:
	# JSON is a text format for data. Broken text gives your fallback ({}) and no red error.
	var broken: Variant = LFJson.parse("{not json", {})
	print(broken)

	# Good text becomes a Dictionary (a set of named values).
	var data: Variant = LFJson.parse('{"hp": 10, "pos": [1, 2]}', {})
	print(data["hp"])

	# A position stored as [x, y] becomes a Vector2.
	print(LFJson.to_vec2(data["pos"]))

	# Something that is not a valid [x, y] gives the fallback you name (here 5, 5).
	print(LFJson.to_vec2("oops", Vector2(5, 5)))
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `{  }` (an empty dictionary), `10.0` (JSON numbers always arrive as decimals), `(1.0, 2.0)` and `(5.0, 5.0)`.
6. Replace the text in quotes with your own JSON, such as the contents of a file you loaded. The second argument of `parse` is what you get back when the text is invalid.

## API

Everything the class offers; you only need the rows used above to get started.

### Methods

| Member | Signature | Description |
|---|---|---|
| `parse` | `static parse(text: String, default: Variant = null) -> Variant` | The value `text` encodes, or `default` when it is not valid JSON. Logs nothing for invalid JSON (Godot itself still warns about an out-of-range number such as `1e999`; see Notes). |
| `parse_object` | `static parse_object(text: String) -> Variant` | The Dictionary `text` encodes, or null when it is not valid JSON or not an object. Logs like `parse`. |
| `vec3` | `static vec3(v: Variant) -> Array` | `[x, y, z]` for a `Vector3` or `Vector3i`. It reads `v.x`, `v.y`, `v.z`: a value without them (an int, a String) is a script error, and one with them (a `Vector4`, a Dictionary with those keys) is read without complaint. |
| `vec2` | `static vec2(v: Variant) -> Array` | `[x, y]` for a `Vector2` or `Vector2i`. Reads `v.x`, `v.y` the same way as `vec3`. |
| `to_vec3` | `static to_vec3(raw: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3` | The vector `raw` encodes when it is an Array (or packed numeric array) of exactly three finite numbers that fit a vector; `fallback` otherwise. |
| `to_vec2` | `static to_vec2(raw: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2` | The same for two numbers. |

## Usage

```gdscript
extends Node3D

func _ready() -> void:
	# Untrusted text: no engine error if it is broken, just the default.
	var settings: Variant = LFJson.parse("{not json", {})
	print(settings)  # {}

	# Only accept a JSON object (a Dictionary).
	var message: Variant = LFJson.parse_object('{"type": "move", "to": [1, 0, 2]}')
	if message == null:
		return  # not JSON, or not an object: dropped quietly

	# Vectors travel as number arrays.
	var target := LFJson.to_vec3(message.get("to"), global_position)  # Vector3(1, 0, 2)
	print(target)

	var reply := JSON.stringify({"position": LFJson.vec3(global_position)})
	print(reply)  # {"position":[0.0,0.0,0.0]}
```

## Notes

- `JSON.parse_string` logs an engine error on bad input; `parse` uses `JSON.new().parse()`, which does not. Use it for anything you don't control (network frames, user files).
- A number too large for a float (`1e999`) is valid JSON. Godot reads it as `inf` and prints an "Exponent too high" warning of its own, which no script can silence. `to_vec2`/`to_vec3` reject such values.
- `parse` cannot tell a valid `null` from a failure when `default` is null. Pass a distinct `default` when that matters.
- Numbers come back as floats (Godot's JSON parser has no ints), so compare with `LFUtils.same_value` or `deep_equal` rather than `==` against an int when the type matters.
- `to_vec2`/`to_vec3` reject bools, strings, nulls, NaN and infinities, numbers too big
  for a vector (above about `3e38`, such as `1e39`), and arrays of the wrong length: a malformed
  payload gives the fallback, not a NaN or infinite vector.
