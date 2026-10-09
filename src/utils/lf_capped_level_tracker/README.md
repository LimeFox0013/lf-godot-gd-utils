# LFCappedLevelTracker

> Per-owner, per-id integer levels, each raised within a cap supplied on every raise.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_capped_level_tracker.gd` |
| **Tests** | `tests/test_lf_capped_level_tracker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when something can be stacked a limited number of times per owner: a perk each
player can take at most 3 times, an upgrade a tower can buy up to level 5, a buff that
stacks to 10. `try_raise(owner, id, cap)` checks the cap and raises in one call, so the
level never goes over. It is the bare counter: when levels should also be worth something
(+2 damage per level), use `LFModifierLevels`; when you want a shop-style grant with a
fallback at the cap (sold out, or turn the overflow into gold), use
`LFModifierGrantService`. Both build on this class.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var tracker := LFCappedLevelTracker.new()

   	# Try to raise the player's fireball four times, with a cap (maximum level) of 3.
   	for attempt in 4:
   		var raised := tracker.try_raise("player_1", &"fireball", 3)
   		var level := tracker.level_for("player_1", &"fireball")
   		print("attempt ", attempt + 1, ": raised = ", raised, ", level is now ", level)
   ```
4. Change `"player_1"` (who owns the level: any name, number or node), `&"fireball"` (what is being levelled; the `&` makes it a *StringName*, Godot's fast kind of name) and `3` (the highest level allowed).
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see levels 1, 2 and 3 go up, then on the fourth attempt `raised = false` and the level stays 3.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `raised` | `signal raised(owner: Variant, id: StringName, new_level: int)` | After every successful raise. |
| `cleared` | `signal cleared` | After `clear()`. |
| `forgotten` | `signal forgotten(owner: Variant)` | After `forget(owner)`, even when the owner held nothing — so listeners drop their own state for it. |
| `level_for` | `level_for(owner: Variant, id: StringName) -> int` | 0 if never raised. Creates nothing. |
| `has_capacity` | `has_capacity(owner: Variant, id: StringName, cap: int) -> bool` | Whether one more raise stays within `cap`. |
| `try_raise` | `try_raise(owner: Variant, id: StringName, cap: int) -> bool` | +1 if within `cap` (emits `raised`) and true; else false, unchanged. `cap <= 0` always rejects. |
| `clear` | `clear() -> void` | Clears everything; emits `cleared`. |
| `forget` | `forget(owner: Variant) -> void` | Drops one owner's levels; emits `forgotten`. |

## Usage

```gdscript
# A script on a game manager.
extends Node

const FIREBALL_MAX := 3

var tracker := LFCappedLevelTracker.new()


func _ready() -> void:
	tracker.raised.connect(_on_raised)
	for i in 4:                                   # the 4th try is refused
		if !tracker.try_raise("player_1", &"fireball", FIREBALL_MAX):
			print("fireball is maxed")
	print(tracker.level_for("player_1", &"fireball"))                 # 3
	print(tracker.has_capacity("player_2", &"fireball", FIREBALL_MAX))  # true
	tracker.forget("player_1")                    # the player left: drop their levels


func _on_raised(who: Variant, id: StringName, new_level: int) -> void:
	print(who, " raised ", id, " to level ", new_level)
```

## Notes

- The cap is checked inside `try_raise`, so a level can never exceed the cap it was
  raised under. A later, lower cap never lowers a level.
- If an owner is a node or other object, the tracker keeps it in memory until you call `forget(owner)` or `clear()`; forget an owner that
  leaves. Owner keys keep their type: `1` and `"1"` are different owners.
- Ids are StringNames; a String with the same text is the same id.
