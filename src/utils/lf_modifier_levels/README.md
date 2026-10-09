# LFModifierLevels

> Per-owner modifier levels and what they are worth, with cached per-group totals.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_modifier_levels.gd` |
| **Tests** | `tests/test_lf_modifier_levels.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFCappedLevelTracker`, `LFLogger` |

## When to use it

Use it for stacking upgrades that add to stats: a "Might" perk worth +2 damage per level
(up to 3 levels), a "Stride" talent worth +0.5 speed per level, team-wide upgrades that
help every unit. Declare each modifier once, grant levels per owner, and read one summed
Dictionary per group (`{"damage": 4.0, "speed": 0.5}`) to feed into your stat code
(`LFLayeredStats` can take it as a layer as is). For a bare capped counter with no worth
use `LFCappedLevelTracker`; for a purchase limit with a "sold out" or "turn into gold"
fallback, add `LFModifierGrantService` on the same tracker.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var levels := LFModifierLevels.new()

   	# Each level of "might" adds 2 damage. The group "hero" reads it.
   	levels.declare(&"might", {"damage": 2.0}, [&"hero"])

   	# Give the knight two levels of might (the cap, or maximum, is 3).
   	levels.grant("knight", &"might", 3)
   	levels.grant("knight", &"might", 3)

   	print(levels.level_of("knight", &"might"))                 # 2
   	print(levels.bonus_of("knight", &"might", "damage"))       # 4.0
   	print(levels.bonuses_for("knight", &"hero"))               # { "damage": 4.0 }
   ```
4. Change `&"might"` (the modifier's name), `{"damage": 2.0}` (a *Dictionary*, a list of name-and-value pairs: each level adds 2 to damage; add more pairs for more stats), `[&"hero"]` (the group of owners that read it) and `3` (the highest level a grant may reach).
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see `2` (the knight's level), `4.0` (two levels of +2 damage) and `{ "damage": 4.0 }`.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFModifierLevels.new(initial_shared_owner: Variant = null, shared_tracker: LFCappedLevelTracker = null)` | The shared owner's levels count for every owner. Pass a tracker to share one. |
| `raised` | `signal raised(owner: Variant, id: StringName, new_level: int)` | An owner's own level went up (relayed from the tracker). |
| `shared_owner` | `var shared_owner: Variant` (read-only) | The owner whose levels count for everyone; null for none. |
| `tracker` | `var tracker: LFCappedLevelTracker` (read-only) | The level counter underneath. |
| `declare` | `declare(id: StringName, bonus_per_level: Dictionary = {}, groups: Array[StringName] = [], cap_bonus_applies := true) -> bool` | Each level adds `bonus_per_level[key]` to `key`. `groups` name who reads it (a group named twice counts once). A second declaration of an id is an error (false). |
| `is_declared` | `is_declared(id: StringName) -> bool` | Whether `id` was declared. |
| `declared_ids` | `declared_ids() -> Array[StringName]` | Every id, in declaration order. |
| `ids_in` | `ids_in(group: StringName) -> Array[StringName]` | The group's ids, in declaration order. |
| `grant` | `grant(owner: Variant, id: StringName, cap: int) -> bool` | +1 to `owner`'s own level, up to `effective_cap`. False at the cap or for an undeclared id (an error). |
| `has_capacity` | `has_capacity(owner: Variant, id: StringName, cap: int) -> bool` | Whether one more `grant` would pass. |
| `effective_cap` | `effective_cap(owner: Variant, id: StringName, cap: int) -> int` | `cap` plus the owner's cap bonus when `id` accepts it. |
| `add_cap_bonus` | `add_cap_bonus(owner: Variant, amount: int) -> void` | Raises every accepting cap of `owner` by `amount` (adds up). |
| `cap_bonus_of` | `cap_bonus_of(owner: Variant) -> int` | The owner's total cap bonus. |
| `cap_bonus_for` | `cap_bonus_for(owner: Variant, id: StringName) -> int` | The owner's cap bonus when `id` accepts one, else 0 — pass it to `LFModifierGrantService.new(levels.tracker, levels.cap_bonus_for)` so the service honours the per-id rule. |
| `own_level` | `own_level(owner: Variant, id: StringName) -> int` | The owner's own level. |
| `level_of` | `level_of(owner: Variant, id: StringName) -> int` | Own plus the shared owner's. |
| `bonus_of` | `bonus_of(owner: Variant, id: StringName, key: Variant) -> float` | What `id`'s levels add to `key`. |
| `total_of` | `total_of(owner: Variant, key: Variant, group: StringName) -> float` | Sum over the group. |
| `bonuses_for` | `bonuses_for(owner: Variant, group: StringName) -> Dictionary` | `{key: total}` over the group's held modifiers. Read-only; the same instance until a level feeding it changes. |
| `clear` | `clear() -> void` | Drops levels and cap bonuses; keeps declarations. Levels are cleared in the tracker, so every user of a shared tracker loses them. |
| `forget` | `forget(owner: Variant) -> void` | Drops one owner's levels, cap bonus and snapshots (through the tracker's `forgotten`, so every user of a shared tracker forgets it too). Forgetting the shared owner renews every snapshot. |
| `_bonus_at` | `_bonus_at(id: StringName, key: Variant, level: int) -> float` | Override point in a subclass: default `level × amount`. |

## Usage

```gdscript
# A script on a game manager.
extends Node

# "team" is the shared owner: its levels help every owner.
var levels := LFModifierLevels.new("team")


func _ready() -> void:
	# Each level of "might" adds 2 damage; heroes read it.
	levels.declare(&"might", {"damage": 2.0}, [&"hero"])
	# Each level of "stride" adds 0.5 speed; heroes and summons read it.
	levels.declare(&"stride", {"speed": 0.5}, [&"hero", &"summon"])

	levels.grant("knight", &"might", 3)        # one level, cap 3
	levels.grant("knight", &"might", 3)        # two levels
	levels.grant("team", &"stride", 1)         # helps everyone
	levels.add_cap_bonus("knight", 1)          # the knight's caps are now +1

	print(levels.level_of("knight", &"might"))           # 2
	print(levels.bonus_of("knight", &"might", "damage"))  # 4.0
	print(levels.bonuses_for("knight", &"hero"))         # { "damage": 4.0, "speed": 0.5 }
	print(levels.total_of("archer", "speed", &"hero"))   # 0.5 (from the team level)
```

A curve instead of a flat amount per level, in its own script file:

```gdscript
class_name DiminishingLevels
extends LFModifierLevels


# Each level is worth a little less than the one before.
func _bonus_at(id: StringName, key: Variant, level: int) -> float:
	var per_level := super._bonus_at(id, key, 1)
	return per_level * (1.0 - pow(0.8, level)) / 0.2
```

## Notes

- A snapshot from `bonuses_for` is a stable value: hold it on a unit to keep the bonuses
  it was created with, or ask again to get the current ones. Asking repeatedly returns the
  cached Dictionary (two Dictionary lookups) until a level of that owner (or the shared
  owner) changes.
- A cap bounds an owner's own levels only; the shared owner's levels add on top.
- An id declared with `cap_bonus_applies = false` keeps exactly the cap `grant()` is given.
- For a purchase cap per offer (how often something can be bought, separate from the
  level it raises), use `LFModifierGrantService`.
- Owners are Dictionary keys: `1` and `"1"` are different owners, while `"knight"` and
  `&"knight"` are the same one (the shared owner too).
- If an owner is a node or other object, it (and its cap bonus and snapshots) is kept in memory until `forget(owner)` or
  `clear()`; call `forget` when an owner leaves.
- If you override `_bonus_at` (see the curve example above): `bonus_of` asks about any key, but `total_of` and `bonuses_for`
  only ask about the keys an id declared in `bonus_per_level` — declare every key an
  override can return, even with 0.
- Snapshots are renewed only when a level changes, so an overridden `_bonus_at` must not
  read state that changes on its own; otherwise `bonuses_for` goes stale.
- Pairing with `LFModifierGrantService`: pass `cap_bonus_for` (per id), not `cap_bonus_of`
  (which ignores `cap_bonus_applies`).
