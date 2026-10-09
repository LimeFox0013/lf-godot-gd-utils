# LFObjectIdRegistry

> Gives objects short readable ids like `unit-1` and finds the object again from its id.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_object_id_registry.gd` |
| **Tests** | `tests/test_lf_object_id_registry.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it when you need to name an object in text that outlives the object reference: a
network message ("unit-7 attacks unit-12"), a replay, a save file or a log line. Godot's
`get_instance_id()` gives a big number that changes every run; this
registry hands out short ids in order (`unit-1`, `unit-2`, ...), never reuses one within
the registry, and maps
it back to the live object with `object_for`. For ids inside one running scene only, a
direct object reference is simpler.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

# Ids will read unit-1, unit-2, ...
var units := LFObjectIdRegistry.new("unit")


func _ready() -> void:
	var knight := Node.new()
	var archer := Node.new()
	add_child(knight)
	add_child(archer)

	print(units.id_for(knight))  # the first request creates the id
	print(units.id_for(archer))
	print(units.id_for(knight))  # asking again gives the same id

	# Go from the text id back to the object.
	print(units.object_for("unit-2") == archer)
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `unit-1`, `unit-2`, `unit-1` and `true`.
6. Change `"unit"` to a word that suits your objects ("card", "enemy"). Use the id wherever you need text: a network message, a save file, a log line.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFObjectIdRegistry.new(id_prefix: String)` | Ids read `<prefix>-1`, `<prefix>-2`, ... |
| `prefix` | `var prefix: String` (read-only) | The text before every id; assigning reports an error. |
| `id_for` | `id_for(object: Variant, release_on: Signal = Signal()) -> String` | The object's id, assigned on first call; `release_on` (e.g. a death signal) releases it the first time it fires. A freed object gets `''` and an error. |
| `find_id` | `find_id(object: Variant) -> String` | The object's id, or `''` — never assigns one. |
| `object_for` | `object_for(id: String) -> Object` | The live object holding `id`, or null (released, never issued, or its object was freed). |
| `has_object` | `has_object(object: Variant) -> bool` | Whether the object is live and holds an id. |
| `release` | `release(object: Variant) -> void` | Forgets the object and its id, also when the object was freed meanwhile. |
| `release_id` | `release_id(id: String) -> void` | Forgets the id and its object; a no-op for an unknown or released id. Bind this, not `release`, to a signal the object itself owns. |

The object parameters are `Variant` so a freed object can be passed.

## Usage

```gdscript
extends Node

var units := LFObjectIdRegistry.new("unit")


func _ready() -> void:
	var knight := Node.new()
	add_child(knight)

	# Released automatically when the knight leaves the tree.
	var id := units.id_for(knight, knight.tree_exited)
	print(id)                         # unit-1
	print(units.id_for(knight))       # unit-1 again: same object, same id
	print(units.object_for(id) == knight)  # true
	print(units.has_object(knight))   # true

	knight.queue_free()               # tree_exited fires, the id is released
	await get_tree().process_frame
	print(units.object_for(id))       # <null>
```

## Notes

- The registry keeps a RefCounted object (a Resource, a `RefCounted.new()`) alive until
  its id is released: pass a `release_on` signal or call `release()` when the object is
  done with. A Node or other plain Object is not kept alive; once freed it is forgotten
  (see below).
- `release_on` works with a signal of any arity, and only the call that assigns the id
  connects it: a `release_on` passed for an object that already has an id is ignored.
- The `release_on` hook binds the id, not the object, so a signal the object owns doesn't
  keep it alive through that connection. After a manual release it can only release the
  old id, never a newer one the same object got since.
- A released id is gone for good; re-registering the same object gives it a new id.
- A freed object is handled without errors: `has_object` is false and `find_id` is `''`;
  `object_for(id)` answers null, and `release(object)` or `release_id(id)` forgets it.
  `id_for` reports it and returns `''`.
- Objects freed without a release are forgotten anyway: after max(32, entries left by the
  previous sweep) new ids were assigned, `id_for` drops the entries of freed objects. With
  L entries left by the last sweep (all live then), the registry holds at most
  L + max(32, L) entries, live or not, however many objects came and went; a sweep goes over every entry once.
