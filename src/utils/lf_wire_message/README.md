# LFWireMessage

> Typed network messages as `{type, payload}` dictionaries, and back, with malformed ones refused.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_wire_message.gd` |
| **Tests** | `tests/test_lf_wire_message.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFDictionary` |

## When to use it

Use it when a game sends several kinds of message over a socket and the other side must not
crash on a bad one: a player action, a server event. You list the kinds once; `decode` gives
back the kind and payload, or null for an unknown type or a missing field. Extra checks (a
value in a range) stay in your code.

## Step by step

1. In the Godot editor choose *Scene → New Scene*, add a **Node**, attach a script (the scroll icon) and press *Create*.
2. Replace the script with the code below:

   ```gdscript
   extends Node

   enum Kind { PING, MOVE }

   var codec := LFWireMessage.new({Kind.PING: "ping", Kind.MOVE: "move"}, {Kind.MOVE: ["x", "y"]})


   func _ready() -> void:
   	var wire := codec.encode(Kind.MOVE, {"x": 1, "y": 2})
   	print(wire)                                  # {"type": "move", "payload": {...}}
   	print(codec.decode(wire))                    # {"kind": 1, "payload": {...}}
   	print(codec.decode({"type": "move"}))        # <null>: x and y are missing
   ```
3. Press **F6** and save the scene when asked. The *Output* panel shows the three lines in the comments.

## API

| Member | Signature | Description |
|---|---|---|
| `new` | `LFWireMessage.new(kind_names: Dictionary, required := {})` | `kind_names` is `{kind: wire name}`; `required` is `{kind: [payload keys]}` (a kind not listed needs none). |
| `encode` | `encode(kind: Variant, payload := {}) -> Dictionary` | `{type, payload}`. |
| `encode_text_once` | `encode_text_once(kind: Variant, payload: Dictionary) -> String` | `encode(kind, payload)` as JSON text. The last text is kept: the very same `payload` object (not an equal copy) with the same `kind` returns it without encoding again. Do not change the object in between. |
| `splice_text` | `splice_text(kind: Variant, payload: Dictionary, field: String, field_text: String) -> String` | The JSON text of the message with `field` removed from `payload` and `field_text` (already encoded JSON) put last. Parses to the same message; only the key order differs. |
| `decode` | `decode(message: Dictionary) -> Variant` | `{kind, payload}`, or null when the type is unknown, the payload is not a Dictionary, or a required key is missing. A missing payload counts as `{}`. |

## Usage

```gdscript
extends Node

enum Kind { PING, MOVE }

func _ready() -> void:
	var codec := LFWireMessage.new({Kind.PING: "ping", Kind.MOVE: "move"}, {Kind.MOVE: ["x", "y"]})

	# Send: one text for many peers, encoded once.
	var move := {"x": 1, "y": 2}
	var text := codec.encode_text_once(Kind.MOVE, move)

	# Receive: parse the text, then decode; null means refuse it.
	var decoded: Variant = codec.decode(JSON.parse_string(text))
	if decoded != null and decoded["kind"] == Kind.MOVE:
		print(decoded["payload"])  # { "x": 1.0, "y": 2.0 }

	# A big field shared by many messages is encoded once and spliced in last.
	var state_text := JSON.stringify({"units": [1, 2, 3]})
	print(codec.splice_text(Kind.PING, {"tick": 7, "state": {}}, "state", state_text))
```

## Notes

- Several peers get one message: build the text with `encode_text_once` (or `splice_text` when only a big field is shared) and send the same text to each.
- Wire names must be unique; two kinds with one name decode to the later kind.
- `encode` of a kind that is not listed gives an empty type, which `decode` refuses.
