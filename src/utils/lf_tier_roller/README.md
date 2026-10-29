# LFTierRoller

> Roll a tier by weight with an optional minimum, then pick an item of that tier.

| | |
|---|---|
| **Kind** | [Static](../../../README.md#how-lf-classes-work): call it on the class name |
| **Files** | `lf_tier_roller.gd` |
| **Tests** | `tests/test_lf_tier_roller.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFWeightedPick`, `LFLogger` |

## When to use it

Use it for "roll a rarity, then a random item of that rarity" — the classic card-pack or
chest reward: 60 % common, 25 % rare, 10 % epic, 5 % legendary, then any card of the
rolled rarity. It also handles the awkward cases for you: a minimum rarity (a boss chest is
at least rare), and a rarity with no items in the pool (it moves to the nearest rarity that
has some instead of giving nothing). For a flat weighted list of specific outcomes use
`LFLootTable` or `LFWeightedPick`; for a guaranteed good drop after a bad-luck streak,
combine this with `LFPityTracker`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node

   const RARITY_WEIGHTS := [70.0, 25.0, 5.0]       # chance of tier 0, 1 and 2
   const TIER_OF := {"Stick": 0, "Sword": 1, "Crown": 2}   # each item's tier: 0 common, 1 rare, 2 epic


   func _ready() -> void:
   	var rng := LFRandom.new(5)
   	var items := ["Stick", "Sword", "Crown"]
   	var tier_of := func(item: String) -> int: return TIER_OF[item]

   	# Five ordinary picks.
   	for i in 5:
   		print(LFTierRoller.pick(items, tier_of, RARITY_WEIGHTS, rng))

   	# A boss chest: tier 1 or better, so never the Stick.
   	for i in 5:
   		print("boss: ", LFTierRoller.pick(items, tier_of, RARITY_WEIGHTS, rng, 1))
   ```
4. Change `TIER_OF` to list your own items and the tier of each (a tier is a whole number from 0 up: 0 common, 1 rare ...), and `RARITY_WEIGHTS` to set how likely each tier is (one weight per tier, as shares). The `func(item: String) -> int: ...` line is a small function stored in a variable (a *Callable*) that tells the roller an item's tier. The last number in the boss line (`1`) is the lowest tier allowed.
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see ten item names: mostly `Stick` and `Sword` in the first five, and no `Stick` at all in the five marked `boss:`. The exact names depend on the seed (`5`); they are the same on every run.

## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value". A *Callable* is a function passed around as a value (a method name such as `_my_method`, or an inline `func(x): ...`).

| Member | Signature | Description |
|---|---|---|
| `Fallback` | `enum Fallback { LOWER_FIRST, HIGHER_FIRST }` | Where an empty tier looks first: toward the floor (`LOWER_FIRST`) or upward (`HIGHER_FIRST`), then the other way. |
| `bucket` | `static bucket(items: Array, tier_of: Callable, tier_count: int) -> Array` | `tier_count` arrays of items grouped by `tier_of(item) -> int`; out-of-range tiers are reported and skipped. |
| `pick_from_buckets` | `static pick_from_buckets(buckets: Array, weights: Array, tier_roll: float, item_roll: float, floor_tier: int = 0, fallback: Fallback = Fallback.LOWER_FIRST) -> Variant` | Pure, on rolls you pass in (each 0–1); null when every bucket is empty. A negative `floor_tier` counts as 0; a roll landing on a weight past the last bucket counts as the last bucket. |
| `pick` | `static pick(items: Array, tier_of: Callable, weights: Array, rng: RandomNumberGenerator, floor_tier: int = 0, fallback: Fallback = Fallback.LOWER_FIRST) -> Variant` | Two draws from `rng` (tier, then item); none when `items` is empty (returns null). A null `rng` is reported and picks nothing. |
| `resolve_tier` | `static resolve_tier(buckets: Array, rolled: int, floor_tier: int, fallback: Fallback = Fallback.LOWER_FIRST) -> int` | The tier with items that a rolled tier ends up on (`rolled` clamped into the buckets); -1 when all are empty. |
| `tilt_weights` | `static tilt_weights(base: Array, shift: float, floor_of_first: float) -> Array[float]` | A new weight array with `shift` moved out of the first tier (never below `floor_of_first`) into the others in proportion to their base weights. A negative `shift` counts as 0. |

## Usage

```gdscript
# A script on a card-pack opener.
extends Node

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
const RARITY_WEIGHTS := [60.0, 25.0, 10.0, 5.0]   # one weight per rarity, in order

var rng := LFRandom.new()
var card_pool := [
	{"name": "Squire", "rarity": Rarity.COMMON},
	{"name": "Archer", "rarity": Rarity.COMMON},
	{"name": "Knight", "rarity": Rarity.RARE},
	{"name": "Dragon", "rarity": Rarity.LEGENDARY},   # no EPIC cards: an EPIC roll falls back
]


func _ready() -> void:
	var rarity_of := func(card: Dictionary) -> int: return card.rarity
	# Any rarity.
	var card: Dictionary = LFTierRoller.pick(card_pool, rarity_of, RARITY_WEIGHTS, rng)
	print("you got ", card.name)
	# A boss pack: at least RARE.
	var boss_card: Dictionary = LFTierRoller.pick(card_pool, rarity_of, RARITY_WEIGHTS, rng, Rarity.RARE)
	print("boss pack: ", boss_card.name)

	# Many picks from the same pool: group once, then pick with two rolls each time.
	var buckets := LFTierRoller.bucket(card_pool, rarity_of, RARITY_WEIGHTS.size())
	for i in 3:
		print(LFTierRoller.pick_from_buckets(buckets, RARITY_WEIGHTS, rng.randf(), rng.randf()).name)
```

## Notes

- Tiers below the floor are never rolled — unless no tier at or above it has items, then
  the floor is dropped so a guaranteed pick still yields something.
- A rolled tier with no items falls to the nearest stocked tier in the fallback
  direction (never below the floor), then the other way.
- Weights are per call, so a tilt (luck, difficulty) stays the caller's policy; `tilt_weights` does the arithmetic of one common tilt (luck moves weight out of the first tier).
- In `pick`, `weights.size()` sets how many tiers there are; an item whose tier is past
  it is reported and skipped.
- `pick` sorts `items` into tiers again on every call: one pass over the whole pool, plus
  new arrays. If you pick many times from the same pool, call `bucket` once and then `pick_from_buckets` with two rolls from your generator.
