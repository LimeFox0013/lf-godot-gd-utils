# LFModifierGrantService

> Grants an id to an owner up to a capped count: a hard stop at the cap, or a conversion.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_modifier_grant_service.gd` |
| **Tests** | `tests/test_lf_modifier_grant_service.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFCappedLevelTracker` |

## When to use it

Use it when something can be given only a limited number of times and you must decide
what happens past the limit: a shop that sells a perk at most 3 times and then shows "sold
out", or a chest that, once you own the maximum, turns a duplicate into gold instead of
wasting it. A shop and a chest can share one tracker so both draw down the same cap.
For a bare capped counter use `LFCappedLevelTracker`; to also total what the levels are
worth (+2 damage per level), pair it with `LFModifierLevels`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var grants := LFModifierGrantService.new()

   	# A shop sells at most 2 shields to this player. The third sale is refused.
   	for i in 3:
   		var outcome := grants.grant("player_1", &"shield", 2, _on_shield_granted)
   		print(LFModifierGrantService.Outcome.keys()[outcome])      # GRANTED, GRANTED, REJECTED

   	print("shields owned: ", grants.count_for("player_1", &"shield"))


   func _on_shield_granted() -> void:
   	print("  shield handed over")     # your real code goes here: add it to the inventory
   ```
4. Change `"player_1"` (who receives it), `&"shield"` (what is granted), `2` (the most times it can be granted) and `_on_shield_granted` (the function that runs when a grant succeeds: put your real code there, such as adding the item to an inventory). `Outcome` is an *enum* (a fixed list of named results); `Outcome.keys()[outcome]` turns the result into its name so it can be printed.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see `shield handed over` then `GRANTED`, the same pair again, then `REJECTED` for the third try, and finally `shields owned: 2`.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`). A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`. An *enum* is a fixed list of named results.

| Member | Signature | Description |
|---|---|---|
| `Outcome` | `enum Outcome { GRANTED, REJECTED, CONVERTED }` | What `grant` did: counted it, refused it at the cap, or ran `on_overflow` instead. |
| `granted` | `signal granted(owner: Variant, id: StringName, count: int)` | After a counted grant and its `on_grant`; `count` is the new count. |
| `rejected` | `signal rejected(owner: Variant, id: StringName)` | Hard stop at the cap. |
| `converted` | `signal converted(owner: Variant, id: StringName)` | `on_overflow` ran instead. |
| `_init` | `LFModifierGrantService.new(shared_tracker: LFCappedLevelTracker = null, cap_bonus_of := Callable())` | Counts in `shared_tracker` (or a new one). `cap_bonus_of(owner, id) -> int` (per id) or `cap_bonus_of(owner) -> int` (every id) raises caps; read at each check. |
| `tracker` | `var tracker: LFCappedLevelTracker` (read-only) | Share it between services to draw down one cap. |
| `count_for` | `count_for(owner: Variant, id: StringName) -> int` | How many grants were counted (0 if none). |
| `effective_cap` | `effective_cap(owner: Variant, id: StringName, cap: int) -> int` | `cap` + the owner's bonus (for `id`, with a per-id bonus). |
| `has_capacity` | `has_capacity(owner: Variant, id: StringName, cap: int) -> bool` | Whether one more grant fits under `cap` plus the bonus. |
| `grant` | `grant(owner: Variant, id: StringName, cap: int, on_grant := Callable(), on_overflow := Callable()) -> Outcome` | Below the cap: count, `on_grant()`, `granted`. At the cap: `rejected` without `on_overflow`, else `on_overflow()` and `converted`. |
| `clear` | `clear() -> void` | Forgets every grant. |
| `forget` | `forget(owner: Variant) -> void` | Forgets one owner's grants (announced by the tracker's `forgotten` to everyone sharing it). |

## Usage

```gdscript
# A script on a shop / loot manager.
extends Node

const MAX_OWNED := 2

var grants := LFModifierGrantService.new()
var gold := 0


func _ready() -> void:
	# A shop: never sells past the cap.
	for i in 3:
		var outcome := grants.grant("player_1", &"shield", MAX_OWNED, _apply.bind(&"shield"))
		if outcome == LFModifierGrantService.Outcome.REJECTED:
			print("sold out")

	# A chest: past the cap, the drop turns into 50 gold instead of being wasted.
	grants.grant("player_1", &"shield", MAX_OWNED, _apply.bind(&"shield"), _add_gold.bind(50))
	print(grants.count_for("player_1", &"shield"), " shields, ", gold, " gold")   # 2 shields, 50 gold


func _apply(item: StringName) -> void:
	print("granted ", item)


func _add_gold(amount: int) -> void:
	gold += amount
```

## Notes

- The check and the count are one step; exactly one of `granted`, `rejected` and `converted` fires per call (a counted grant also fires the tracker's `raised`).
- Costs, refunds and what a grant does belong to the caller.
- Pass extra values to a callback with `bind` (`_add_gold.bind(50)`) or an inline function (a *lambda*). `on_grant` and `on_overflow` are called during `grant` and not kept, so any function is fine there. `cap_bonus_of` is kept: a lambda there that uses `self` of a RefCounted object (not a Node) holding this service is a reference cycle, and neither is ever freed. A method holds no reference to its object, and Nodes are not reference-counted.
- Paired with an `LFModifierLevels` on the same tracker, pass `levels.cap_bonus_for` so a
  modifier declared with `cap_bonus_applies = false` keeps its exact cap. A one-argument
  `cap_bonus_of` (such as `levels.cap_bonus_of`) applies to every id.
- If an owner is a node or other object, it is kept in memory until `forget(owner)` or `clear()`.
