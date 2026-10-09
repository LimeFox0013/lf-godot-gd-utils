# LFRandom

> A seedable random source with chance, pick and shuffle, that never touches Godot's global generator.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_random.gd` |
| **Tests** | `tests/test_lf_random.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it whenever randomness should be repeatable: a daily challenge where every player gets
the same map, a replay that must re-run the same fight, or a test that needs the same
"random" result every time. Create one `LFRandom` with a seed and route every roll of a
system through it: `chance(0.25)` for a 25 % proc, `pick(enemies)` for a random target,
`shuffle(deck)` for a card deck. If you never need to replay anything, Godot's global
`randf()` and `Array.pick_random()` are fine. For weighted picks use `LFWeightedPick` or
`LFLootTable`, passing them this generator.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	# Two generators made with the same seed (42) ...
   	var first := LFRandom.new(42)
   	var second := LFRandom.new(42)

   	# ... give the same dice rolls, one after the other.
   	var rolls_a := []
   	var rolls_b := []
   	for i in 5:
   		rolls_a.append(first.randi_range(1, 6))    # a die: 1 to 6
   		rolls_b.append(second.randi_range(1, 6))
   	print(rolls_a)
   	print(rolls_b)
   	print(rolls_a == rolls_b)                      # true: identical

   	# A 25 % chance: true about one time in four.
   	print(first.chance(0.25))
   ```
4. Change `42` to any whole number: that number is the **seed**, the starting point of the random sequence. The same seed always gives the same sequence. Leave the seed out (`LFRandom.new()`) for a different sequence every run. `randi_range(1, 6)` gives a whole number from 1 to 6, both included.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel (bottom of the editor) you should see two identical lists of five numbers, such as `[6, 5, 3, 2, 5]` twice, then `true`, then `true` or `false` for the 25 % chance. Run it again: the dice come out the same every time, which is the point.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value".

Everything `RandomNumberGenerator` has (`seed`, `state`, `randf`, `randf_range`, `randi_range` ...), plus:

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFRandom.new(seed_value: Variant = null)` | Seeds from `seed_value` (any int, -1 included). Without one, seeds randomly (clock mixed with a per-process counter, so sources made together differ). Never reseeds the global generator. |
| `chance` | `chance(fraction: float) -> bool` | True with probability `fraction` (0–1). `>= 1` is always true and `<= 0` or NaN always false, without a roll; otherwise exactly one `randf()`. |
| `pick` | `pick(items: Array) -> Variant` | A random element, or null for an empty array (no roll). |
| `shuffle` | `shuffle(items: Array) -> void` | Fisher–Yates, in place. |

## Usage

```gdscript
# A script on any Node, e.g. a spawner.
extends Node

var rng := LFRandom.new(42)            # same seed -> same rolls every run


func _ready() -> void:
	# A 25 % chance: true about one time in four.
	if rng.chance(0.25):
		print("critical hit!")

	# One random element (null for an empty array).
	var enemies := ["slime", "bat", "skeleton"]
	print("spawning ", rng.pick(enemies))

	# Shuffle in place.
	var deck := [1, 2, 3, 4, 5]
	rng.shuffle(deck)
	print(deck)

	# It is a RandomNumberGenerator too, so it works with other helpers in the library.
	var tier := LFWeightedPick.index([60.0, 30.0, 10.0], rng.randf())
	var heading := LFUtils3D.random_direction_xz(rng)
	print(tier, heading)
```

## Notes

- Only if you write your own class that extends `RandomNumberGenerator`: inside it, a bare
  `randf()` or `randomize()` calls GDScript's global function, not the generator, so it
  touches Godot's shared random state. Write `self.randf()` (as this class does).
- Weighted picks and rolls on the ground plane (XZ) take a generator rather than living here:
  `LFWeightedPick.index(weights, rng.randf())`, `LFUtils3D.random_direction_xz(rng)`,
  `LFUtils3D.random_point_in_circle_xz(center, radius, rng)`.
- Same seed, same calls, same results — any extra or skipped roll shifts every later one.
  `chance()` and `pick()` deliberately skip the roll for certain or empty cases.
- `Array.pick_random()`, the global `randf()` and `Array.shuffle()` use Godot's shared
  generator, which you cannot replay; route a system through one `LFRandom` to make it replayable.
