# LFInvertIndex, LFIndexingRule

> Files stored items under the values they hold, so a lookup like "every card with the tag `fire`" reads only the matching buckets.

| | |
|---|---|
| **Files** | `lf_invert_index.gd`, `lf_indexing_rule.gd` |
| **Tests** | `tests/test_lf_invert_index.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFDictionary` (`get_by_steps`), `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFInvertIndex` | Object: create it with `.new()` |
| `LFIndexingRule` | Object: create it with `.new()` |

## When to use it

Use it when you keep many items (units, cards, inventory entries) and often ask "which of
them have this value?", such as every card with the tag `fire` or every unit of type
`ranged`. Looping over all items checks every one of them on each question; the index reads only
the buckets for the values you ask about. Adding and removing Objects does not scan lists;
Dictionaries have a few slower cases (see Notes). You describe what to file items by
with `LFIndexingRule`s (a path like `"type"` or `"tags"`), add items, and look them up by
rule name and values. For a single lookup by a unique id, a plain Dictionary
(`{id: item}`) is simpler.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

func _ready() -> void:
	# One rule: file every item under the value of its "type" entry.
	var index := LFInvertIndex.new([LFIndexingRule.new("type")])

	# Items are Dictionaries here (a Dictionary is a set of named values).
	var sword := {"name": "Sword", "type": "melee"}
	var bow := {"name": "Bow", "type": "ranged"}
	index.add(sword)
	index.add(bow)

	# Ask: which items have type "melee"? The answer is a list of items.
	var found := index.get_by_values("type", ["melee"])
	print(found.size())     # 1
	print(found[0]["name"]) # Sword
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `1` and `Sword`.
6. For your own data, change `"type"` to the name of the entry you want to search by. Add a second rule, such as `LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY)`, to also search inside lists (see Usage below).

## API

Everything the class offers; you only need the rows used above to get started.

### LFInvertIndex

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFInvertIndex.new(rules: Array[LFIndexingRule])` | Two rules with the same name are reported (the second is dropped). |
| `add` | `add(item: Variant) -> void` | Indexes a Dictionary or Object under every value its rules extract; re-adding re-indexes. |
| `remove` | `remove(item: Variant) -> void` | By identity, so an item changed after `add` still comes out; unknown items are ignored. |
| `get_by_values` | `get_by_values(rule_name: String, values: Array) -> Array` | Items indexed under any of `values`, each once, in first-match order. An unknown rule name is reported. |
| `has` | `has(item: Variant) -> bool` | Whether `item` is indexed (by identity). |
| `size` | `size() -> int` | How many items are indexed. |
| `items` | `items() -> Array` | Every item, in insertion order (a copy; re-adding moves an item to the end). |
| `clear` | `clear() -> void` | Removes every item; the rules stay. |

### LFIndexingRule

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFIndexingRule.new(property_path: String, rule_target: Target = Target.VALUE, rule_name: String = "")` | `rule_name` defaults to the path; give one when two rules share a path. |
| `name` | `var name: String` | What lookups call the rule; defaults to the path. |
| `path` | `var path: String` | The dot-separated path read inside each item (Dictionaries and Objects). |
| `target` | `var target: Target` | How the value at `path` becomes index values. |
| `Target` | `enum { VALUE, ARRAY, DICTIONARY_KEYS, DICTIONARY_VALUES }` | The value itself; each element of an Array or packed array; each key; each value. |
| `values_of` | `values_of(item: Variant) -> Array` | The values the item is indexed under; a missing path or a wrong-shaped value gives none. |

## Usage

```gdscript
extends Node

func _ready() -> void:
	var cards := LFInvertIndex.new([
		LFIndexingRule.new("type"),                                 # file by the "type" value
		LFIndexingRule.new("tags", LFIndexingRule.Target.ARRAY),    # file under each tag
	])
	var sword := {"id": 1, "type": "melee", "tags": ["fast", "cheap"]}
	var bow := {"id": 2, "type": "ranged", "tags": ["slow"]}
	cards.add(sword)
	cards.add(bow)

	print(cards.get_by_values("type", ["melee"]))           # [sword]
	print(cards.get_by_values("tags", ["cheap", "slow"]))   # [sword, bow]
	print(cards.size())                                     # 2

	# Changed an item? Add it again to re-file it under its new values.
	bow["tags"].append("cheap")
	cards.add(bow)
	print(cards.get_by_values("tags", ["cheap"]).size())    # 2

	cards.remove(sword)
	print(cards.has(sword))                                 # false
```

## Notes

- Items are tracked by identity (the very same object, not an equal-looking copy): two equal Dictionaries are two items, and a Dictionary changed after `add` is still removed by `remove` (re-`add` it to re-index its new values, as often as you like: an item always has exactly one record).
- Cost, Objects: `add`, `remove` and `has` take time proportional to the number of rules and
  values the item is filed under, however many items share a bucket (16,000 Objects under one
  value are added, looked up and removed in well under a second). A lookup takes time
  proportional to the number of items it returns.
- Cost, Dictionaries: GDScript gives a Dictionary no identity handle, so one is found by its
  content hash while it is unchanged since `add`, which is constant time. Two cases are
  slower, each a scan of all Dictionary items: `remove` or `has` of a Dictionary that changed
  after `add` or was never added; the first read (`get_by_values`, `size`, `items`, `has`,
  `remove`) after adds, which checks whether an added Dictionary is a changed one that was
  already indexed (one pass over all Dictionaries, or a pass per added one when only a few
  were added). Adding and then reading one Dictionary at a time therefore costs time
  proportional to the number of Dictionaries per step (4,000 steps took about a second).
  Many Dictionaries with identical content also share a hash, and then `add` compares
  against each of them (4,000 identical ones took about 1.5 seconds). Give Dictionary items
  a distinguishing value, or use Objects, when you keep tens of thousands of them.
- Adding an already-indexed object re-indexes it (it is removed first).
- A bucket (the list of items filed under one value) is dropped when it becomes empty.
- An object whose rule path crosses a scalar (e.g. `type.name` on `{type = 3}`) is simply not indexed under that rule.
- A value of the wrong shape for its target (a String under `ARRAY`) indexes nothing.
- Values match like Dictionary keys: `"melee"` and `&"melee"` are the same value, but `1`
  and `1.0` are not (numbers read from JSON are floats, so look them up as floats).
- An Object item freed without `remove()` stays in its buckets, and lookups return it as a freed instance: remove items before freeing them (`remove` still accepts the freed instance afterwards). `has()` checks items one by one, Objects included.
