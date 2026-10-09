# LFLayeredStats

> One owner's stats, each folded from declared layers through each layer's own combine rule.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_layered_stats.gd` |
| **Tests** | `tests/test_lf_layered_stats.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to compute final stats from several sources that combine in a fixed order: a
unit's base damage, plus flat bonuses from perks, capped at a maximum, then multiplied by
a rage buff — `(10 + 4) min 50 × 1.5 = 21`. You declare the layers once (in a shared
`Layout`, so the declarations are stored once however many units use them), then set or feed values per unit and call
`resolve("damage")`. For a single number with a few modifiers, plain arithmetic is enough;
to track perk levels and total their bonuses per stat, use `LFModifierLevels`, whose
`bonuses_for` Dictionary can be one layer here as is.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var stats := LFLayeredStats.new()

   	# Layers are applied in the order you declare them.
   	stats.declare_layer(&"base", LFLayeredStats.sum)               # add
   	stats.declare_layer(&"flat", LFLayeredStats.sum)               # add
   	stats.declare_layer(&"mult", LFLayeredStats.product, 1.0)      # multiply (1.0 = no change)

   	stats.set_value(&"base", "damage", 10.0)
   	stats.set_value(&"flat", "damage", 4.0)      # e.g. a perk: +4
   	stats.set_value(&"mult", "damage", 1.5)      # e.g. a rage buff: x1.5

   	print(stats.resolve("damage"))               # (10 + 4) x 1.5 = 21.0

   	stats.clear_layer(&"mult")                   # the buff ends
   	print(stats.resolve("damage"))               # 14.0
   ```
4. Change the layers to suit your game: `declare_layer(name, how_to_combine, starting_value)`. `LFLayeredStats.sum` adds, `product` multiplies, `min_of` caps, `max_of` sets a floor. The starting value is what a layer contributes when nothing is set for a stat: 0 for adding, 1 for multiplying. Then set a value per layer and stat name (`"damage"` is any name you like).
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see `21.0` and then `14.0` once the multiplier layer is cleared.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`).

### LFLayeredStats.Layout (shareable declarations)

| Member | Signature | Description |
|---|---|---|
| `declare` | `declare(layer_key: Variant, combine: Callable, identity: float = 0.0) -> void` | Adds the next layer. `combine(running_total, layer_value) -> float`; an invalid Callable is reported and the layer not declared. Declaring again swaps rule and identity, keeping the position. |
| `has` | `has(layer_key: Variant) -> bool` | Whether the layer is declared. |
| `size` | `size() -> int` | How many layers are declared. |
| `identity_of` | `identity_of(layer_key: Variant) -> float` | The layer's identity; 0.0 for an undeclared layer. |

### LFLayeredStats

| Member | Signature | Description |
|---|---|---|
| `sum`, `product`, `min_of`, `max_of` | `static sum(total: float, value: float) -> float` (same shape for all four) | Stock combine rules; pair them with identities 0, 1, `INF`, `-INF`. |
| `_init` | `LFLayeredStats.new(layout: Layout = null)` | Shares `layout`, or starts with a private empty one. |
| `declare_layer` | `declare_layer(layer_key: Variant, combine: Callable, identity: float = 0.0) -> void` | Declares on this instance; with a shared layout, switches to a private copy first. |
| `has_layer` | `has_layer(layer_key: Variant) -> bool` | Whether the layer is declared. |
| `set_layer_values` | `set_layer_values(layer_key: Variant, values: Dictionary) -> void` | Adopts `values` by reference; it is never written to. Replaces, never merges. |
| `get_layer_values` | `get_layer_values(layer_key: Variant) -> Dictionary` | The current dictionary (a shared read-only empty one when unset). Read-only. |
| `get_value` | `get_value(layer_key: Variant, stat_key: Variant) -> float` | Stored value or the layer's identity. |
| `set_value` | `set_value(layer_key: Variant, stat_key: Variant, value: float) -> void` | Copies an adopted dictionary first. |
| `accumulate` | `accumulate(layer_key: Variant, stat_key: Variant, value: float) -> float` | Folds `value` in through the layer's rule (from its identity), stores and returns it. |
| `clear_layer` | `clear_layer(layer_key: Variant) -> void` | Drops every value of the layer. |
| `resolve` | `resolve(stat_key: Variant) -> float` | First layer seeds the total; each later layer combines in; unset keys use the identity. 0.0 with no layers. Creates no arrays, dictionaries or objects of its own (your combine rules may). |

## Usage

```gdscript
# A script on a unit.
extends Node

# Once, for every unit: base, then flat bonuses, then a cap, then multipliers.
static var layout := _make_layout()

var stats := LFLayeredStats.new(layout)


static func _make_layout() -> LFLayeredStats.Layout:
	var made := LFLayeredStats.Layout.new()
	made.declare(&"base", LFLayeredStats.sum)
	made.declare(&"flat", LFLayeredStats.sum)
	made.declare(&"cap", LFLayeredStats.min_of, INF)     # INF: no cap until one is set
	made.declare(&"mult", LFLayeredStats.product, 1.0)   # 1.0: no change until one is set
	return made


func _ready() -> void:
	stats.set_value(&"base", "damage", 10.0)
	stats.set_layer_values(&"flat", {"damage": 4.0})   # e.g. a perk bonus Dictionary; never modified
	stats.set_value(&"cap", "damage", 50.0)
	stats.accumulate(&"mult", "damage", 1.5)          # a rage buff: x1.5
	print(stats.resolve("damage"))                     # (10 + 4) min 50 x 1.5 = 21.0
	stats.clear_layer(&"mult")                         # the buff ends
	print(stats.resolve("damage"))                     # 14.0
```

## Notes

- Nothing is cached: `resolve()` recomputes the answer every time, so it always reflects the latest values.
- Values and combine results must be numbers.
- A Dictionary from elsewhere (for example an `LFModifierLevels.bonuses_for` result)
  can feed many instances without being copied; this class never changes it.
- A layer that only caps uses `min_of`/`max_of` with an `INF`/`-INF` identity.
- Naming an undeclared layer in any instance method but `has_layer` (`set_value`,
  `accumulate`, `set_layer_values`, `clear_layer`, `get_value`, `get_layer_values`) is
  reported; writes change nothing, reads return 0.0 or the empty dictionary.
- A derived stat (a weighted sum of others) is a short loop over `resolve()`.
