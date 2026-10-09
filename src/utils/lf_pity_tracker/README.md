# LFPityTracker

> A bad-luck guarantee: after a streak of low outcomes, the next one is floored.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_pity_tracker.gd` |
| **Tests** | `tests/test_lf_pity_tracker.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when bad luck should not last forever: "if ten chests in a row give only common
items, the next one is at least rare", or "a boss drop is guaranteed after 20 kills
without one". Record every outcome; when the guarantee is on, `floor_tier()` tells you the
minimum tier for the next roll. It does not roll anything itself, so the guarantee holds
only if your roll respects that minimum — pair it with
`LFTierRoller` (which takes that minimum tier), or, while `is_active()`, roll your
`LFLootTable` with a filter that accepts only good enough entries
(`loot.roll(rng, accept)`; see the LFLootTable README, "Guaranteed drops").

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	# After 3 misses in a row, the next result must be at least tier 1.
   	var pity := LFPityTracker.new(3, 1)
   	pity.activated.connect(_on_activated)

   	for i in 4:
   		print("minimum tier for this roll: ", pity.floor_tier())
   		pity.record(0)                                  # a bad result: tier 0

   	pity.record(1)                                      # a good result resets the streak
   	print("after a good result: ", pity.floor_tier())


   func _on_activated() -> void:
   	print("bad luck! the next roll is guaranteed")
   ```
4. Change `LFPityTracker.new(3, 1)`: the first number is how many bad results in a row switch the guarantee on, the second is the tier that counts as good (tiers are whole numbers you define, for example 0 common, 1 rare, 2 epic). `activated` is a *signal* (an event other code can listen to); `connect(_on_activated)` makes Godot call `_on_activated` when it happens.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see the minimum tier stay 0 for three rolls, the "bad luck" message appear after the third bad result, then the minimum tier become 1, and finally drop back to 0 after a good result.

## API

Everything the class offers; you only need the rows used above to get started. A *signal* is an event other code can listen to: `object.signal_name.connect(my_function)`.

| Member | Signature | Description |
|---|---|---|
| `activated` | `signal activated` | When a miss brings the streak to `streak_length` (once per streak). Lowering `streak_length` to or below the current streak turns the guarantee on silently. |
| `streak_length` | `var streak_length: int` | Misses in a row needed to turn the guarantee on; below 1 turns it off. |
| `threshold` | `var threshold: int` | The tier that counts as a hit, and the minimum tier while the guarantee is on. |
| `streak` | `var streak: int` | Misses in a row so far. |
| `DEFAULT_STREAK_LENGTH` | `const DEFAULT_STREAK_LENGTH := 10` | Misses in a row needed by default. |
| `DEFAULT_THRESHOLD` | `const DEFAULT_THRESHOLD := 1` | The default tier that counts as a hit. |
| `_init` | `LFPityTracker.new(initial_streak_length := DEFAULT_STREAK_LENGTH, initial_threshold := DEFAULT_THRESHOLD)` (10, 1) | Turns on after `initial_streak_length` outcomes in a row below `initial_threshold`. |
| `is_active` | `is_active() -> bool` | The streak has reached its length; stays on until a hit. |
| `floor_tier` | `floor_tier(base := 0) -> int` | `max(base, threshold)` while active, else `base`. |
| `record` | `record(tier: int) -> void` | At or above `threshold` is a hit (resets), else a miss. |
| `record_outcome` | `record_outcome(hit: bool) -> void` | The same, for outcomes without tiers (e.g. "dropped something"). |
| `reset` | `reset() -> void` | Clears the streak; announces nothing. |

## Usage

```gdscript
# A script on a chest spawner.
extends Node

enum Rarity { COMMON, RARE, EPIC }
const WEIGHTS := [80.0, 17.0, 3.0]       # chance of each rarity

var rng := LFRandom.new()
# After 5 chests in a row below RARE, the next one is at least RARE.
var pity := LFPityTracker.new(5, Rarity.RARE)
var pool := [
	{"name": "stick", "rarity": Rarity.COMMON},
	{"name": "sword", "rarity": Rarity.RARE},
	{"name": "crown", "rarity": Rarity.EPIC},
]


func _ready() -> void:
	pity.activated.connect(func(): print("bad luck! the next chest is guaranteed"))
	for i in 10:
		open_chest()


func open_chest() -> void:
	var min_tier := pity.floor_tier()     # COMMON normally, RARE while the guarantee is on
	var item: Dictionary = LFTierRoller.pick(pool, func(it): return it.rarity, WEIGHTS, rng, min_tier)
	pity.record(item.rarity)              # a RARE or better resets the streak
	print(item.name)
```

## Notes

- One tracker is one shared streak across everything recorded into it.
- With an `LFLootTable`: roll `loot.roll(rng, accept)` while `is_active()` (it never gives
  nothing and lands only on entries `accept` takes, such as `entry.content.tier >= pity.threshold`),
  a plain `loot.roll(rng)` otherwise, and record a null drop with `record_outcome(false)`.
- Situational floors (a final wave, a boss) are the caller's; combine them with `maxi`.
- Tiers are plain ints; use your own enum as above.
- Avoid naming a local `floor`: it shadows GDScript's built-in `floor()`.
