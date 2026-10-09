# LFUnlockTree

> The rules of a tree bought level by level: geometric cost growth, a maximum level, prerequisites owned at least once, and a round-robin budget spend.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_unlock_tree.gd` |
| **Tests** | `tests/test_lf_unlock_tree.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (reports an invalid limit or cost) |

## When to use it

Use it for skill trees, tech trees and upgrade shops where each node can be bought several
times at a growing price: "Sharp Blades" costs 100, then 200, then 400 points, up to level
3, and "Brutal Strikes" needs at least one level of Sharp Blades first. It answers "can I
buy the next level?", "what does it cost?" and "how much was spent in total?", and spends
a budget for an AI opponent one level per node per pass. Your nodes stay your own Dictionaries or Resources
(read by field name) and you keep the levels and points yourself. To lay a tree out on
screen by prerequisite depth, use `LFGraph.layer_depths`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var rules := LFUnlockTree.new()
   	var sharp := {"id": "sharp", "base_cost": 100.0, "max_level": 3, "cost_growth": 2.0}

   	# What each level costs: 100, 200, 400.
   	for level in [1, 2, 3]:
   		print("level ", level, " costs ", rules.cost_for_level(sharp, level))

   	# What the player owns so far: nothing.
   	var owned := {}
   	var level_of := func(id) -> int: return owned.get(id, 0)

   	print(rules.can_buy_next(sharp, level_of, 150.0))     # true: level 1 costs 100
   	print(rules.can_buy_next(sharp, level_of, 50.0))      # false: too expensive
   ```
4. Change the node `sharp`: `base_cost` is the price of level 1, `cost_growth` multiplies the price at each level (2.0 doubles it), `max_level` is how many levels can be bought. A node is just a Dictionary (a list of name-and-value pairs). `owned` is where you record what the player has bought; `level_of` is a small function (a *Callable*) that looks a level up in it. Add `"prerequisites": ["other_id"]` to a node to require another node first.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see `level 1 costs 100.0`, `level 2 costs 200.0`, `level 3 costs 400.0`, then `true` (150 points can buy level 1) and `false` (50 cannot).

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`).

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFUnlockTree.new(fields: Dictionary = {})` | Renames any of the fields read from a node: `{"id": "skill_id", "base_cost": "price"}`. Any other key is ignored and reported through `LFLogger` as an error naming it. |
| `DEFAULT_ID_FIELD`, `DEFAULT_BASE_COST_FIELD`, `DEFAULT_MAX_LEVEL_FIELD`, `DEFAULT_COST_GROWTH_FIELD`, `DEFAULT_PREREQUISITES_FIELD` | `const DEFAULT_ID_FIELD := &"id"` (and so on) | The field names read when `new()` renames none: `id`, `base_cost`, `max_level`, `cost_growth`, `prerequisites`. |
| `id_field`, `base_cost_field`, `max_level_field`, `cost_growth_field`, `prerequisites_field` | `var id_field: StringName = DEFAULT_ID_FIELD` (and so on) | The field names read from a node, defaulting to `id`, `base_cost`, `max_level`, `cost_growth`, `prerequisites`. May be changed at any time. |
| `cost_at` | `static cost_at(base_cost: float, cost_growth: float, level: int) -> float` | `base_cost × cost_growth^(level − 1)`; level 1 is the first purchase. |
| `cost_for_level` | `cost_for_level(node: Variant, level: int) -> float` | `cost_at` with the node's fields. |
| `id_of` | `id_of(node: Variant) -> Variant` | The node's id (null when absent). |
| `max_level_of` | `max_level_of(node: Variant) -> int` | The node's maximum level (1 when absent). |
| `can_buy_next` | `can_buy_next(node: Variant, level_of: Callable, budget: float) -> bool` | Not past the maximum, the next level affordable (a NaN cost or budget never is), every prerequisite owned at least once; false for a null node. `level_of(id) -> int`. |
| `spent` | `spent(nodes: Array, levels: Dictionary) -> float` | What `levels` cost over `nodes`; levels past a maximum count as the maximum. |
| `spend_round_robin` | `spend_round_robin(pool: Array, levels: Dictionary, limit: float, level_of_override := Callable()) -> float` | Buys into `levels` (in place) for at most `limit`: one level per node per pass, in pool order, until nothing fits. Returns what it spent. Given `level_of_override(id) -> int`, prerequisites are read only through it (a prerequisite bought in this same call counts only if it reads `levels` too). A NaN, infinite or negative `limit` is reported and buys nothing (returns 0); a null node, or one whose next level costs a negative amount or NaN (reported), is skipped for the rest of the call. |

## Usage

```gdscript
# A script on a skill-tree screen.
extends Node

var rules := LFUnlockTree.new()
var tree := [
	{"id": "sharp", "base_cost": 100.0, "max_level": 3, "cost_growth": 2.0},   # 100, 200, 400
	{"id": "brutal", "base_cost": 300.0, "prerequisites": ["sharp"]},          # one level
]
var owned := {"sharp": 1}                  # what the player has bought
var points := 500.0


func _ready() -> void:
	try_buy(tree[0])                        # sharp level 2 for 200 points
	try_buy(tree[1])                        # brutal for 300 points
	print(owned, " ", points)               # { "sharp": 2, "brutal": 1 } 0.0
	print(rules.spent(tree, owned))         # 600.0 (100 + 200 + 300)
	print(opponent_build())                 # { "sharp": 2, "brutal": 1 }: 600 of 800 (sharp 3 costs 400)


func try_buy(node: Dictionary) -> void:
	if !rules.can_buy_next(node, _level_of, points):
		return
	var next: int = owned.get(node.id, 0) + 1
	points -= rules.cost_for_level(node, next)
	owned[node.id] = next


func _level_of(id: Variant) -> int:
	return owned.get(id, 0)


# An opponent's build: spend 800 points evenly over the tree.
func opponent_build() -> Dictionary:
	var levels := {}
	rules.spend_round_robin(tree, levels, 800.0)
	return levels
```

Reading your own node type as it is (here a Resource with fields `skill_id`, `points_cost`
and `needs`):

```gdscript
var rules := LFUnlockTree.new({"id": "skill_id", "base_cost": "points_cost", "prerequisites": "needs"})
```

## Notes

- A node without `max_level` has one level; without `cost_growth`, no growth; without
  `prerequisites`, none. `base_cost` should always be set (0 when absent).
- A prerequisite counts once it has any level; its own level beyond that does not matter.
- Round robin (one level per node, taking turns) spreads a budget: a cheap node gets one
  level per pass like the others, and only keeps taking levels once the others no longer
  fit (or are maxed). Order the pool to set priorities, and call it again with a different pool to
  spend what is left over elsewhere.
- Costs and budgets are floats; the caller owns the points and the levels.
