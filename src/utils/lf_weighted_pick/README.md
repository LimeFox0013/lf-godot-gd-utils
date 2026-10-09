# LFWeightedPick

> A pure weighted pick: the index a caller-supplied roll lands on, by cumulative walk.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_weighted_pick.gd` |
| **Tests** | `tests/test_lf_weighted_pick.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it when some outcomes should be more likely than others and you only need *which
one*: which enemy type spawns (slimes common, dragons rare), which tier a reward rolls,
which line of dialogue an NPC says. Give it a list of weights and a roll from 0 to 1; it
returns the index. For a ready-made loot table with payloads, a "nothing" share and nested
tables, use `LFLootTable`; for "roll a rarity, then an item of that rarity", use
`LFTierRoller`; for equally likely picks, `LFRandom.pick`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node

   const ENEMIES := ["slime", "goblin", "dragon"]
   const WEIGHTS := [70.0, 25.0, 5.0]   # slimes common, dragons rare (one weight per enemy)


   func _ready() -> void:
   	var rng := LFRandom.new(1234)
   	var counts := {"slime": 0, "goblin": 0, "dragon": 0}

   	# Pick 1000 times and count what came up.
   	for i in 1000:
   		var index := LFWeightedPick.index(WEIGHTS, rng.randf())   # randf(): a number from 0 to 1
   		counts[ENEMIES[index]] += 1

   	print(counts)
   ```
4. Change `ENEMIES` and `WEIGHTS` for your own game. They are lists that line up: the first weight belongs to the first enemy, and so on. A weight is a share, not a percentage: `[70, 25, 5]` and `[14, 5, 1]` behave the same. Change `1234` (the random seed) or remove it for different results each run.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see something close to `{ "slime": 716, "goblin": 230, "dragon": 54 }`: about 70 %, 25 % and 5 % of 1000 picks. The counts are random, so they are usually near those shares rather than exactly 700, 250 and 50.

## API

Everything the class offers; you only need the rows used above to get started. A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`).

| Member | Signature | Description |
|---|---|---|
| `index` | `static index(weights: Array, roll: float, from := 0) -> int` | The index `roll` (in [0, 1)) lands on, among indices `from` onward (a negative `from` counts from 0), each weighted by its share of their total. A zero, negative, NaN or `INF` weight is never chosen and doesn't change the total. A roll at or below 0 picks the first positive weight; at or above 1 (`randf()` can return 1.0), or NaN, the last. Returns `-1` when nothing can be chosen: `weights` empty, `from >= weights.size()`, or no positive weight from `from` on. Never an index before `from`. |
| `index_by` | `static index_by(count: int, weight_at: Callable, roll: float, from := 0) -> int` | `index` with the weights read through `weight_at(i) -> float` for each `i` below `count` — for weights held elsewhere (table entries, computed shares). Same rules. Bind `weight_at` once and reuse it rather than building a new lambda per roll. |

## Usage

```gdscript
# A script on any Node, e.g. an enemy spawner.
extends Node

const ENEMIES := ["slime", "goblin", "dragon"]
const WEIGHTS := [70.0, 25.0, 5.0]       # slimes common, dragons rare

var rng := LFRandom.new(1234)           # seeded: the same spawns every run


func _ready() -> void:
	var i := LFWeightedPick.index(WEIGHTS, rng.randf())
	print("spawning ", ENEMIES[i])

	# Skip the first index (e.g. a minimum tier): only goblins or dragons.
	var tougher := LFWeightedPick.index(WEIGHTS, rng.randf(), 1)
	print("elite: ", ENEMIES[tougher])

	# Weights stored on other objects, read through a function.
	var offers := [{"name": "sword", "weight": 3.0}, {"name": "shield", "weight": 1.0}]
	var weight_of := func(index: int) -> float: return offers[index].weight
	var offer := LFWeightedPick.index_by(offers.size(), weight_of, rng.randf())
	if offer != -1:                       # -1 means nothing could be picked
		print("shop offers ", offers[offer].name)
```

## Notes

- The roll is an argument on purpose — pass a seeded generator's value (`LFRandom`,
  `rng.randf()`) for replayable picks, or a fixed test value; the global `randf()` uses
  Godot's shared generator. For a payload-carrying table with a "nothing" share, use `LFLootTable`.
- `-1` means "nothing to pick"; check for it whenever every weight from `from` on can be
  zero or negative.
- Weights must be ordinary numbers (`float` or `int`). A NaN weight ("not a number", the
  result of an invalid calculation) and an `INF` weight (Godot's infinity) both count as
  zero, so an `INF` meant as "always" is ignored instead: cap huge weights to a finite
  number yourself.
- Finite weights whose total is past the float range (`[1e308, 1e308]`) still pick by
  share: the running total is scaled down by 2^-64 whenever the next weight would overflow
  it. Once scaled, weights below about 1e-289 lose precision and ones below about 1e-305
  count as zero.
- `index_by` calls `weight_at` up to twice per index, so keep it cheap and stable within
  one call. It pays for a Callable call per weight that `index` does not, so use `index`
  when the weights are already an array.
