# LFLootTable, LFLootEntry

> A weighted table of outcomes with a "nothing" share; nested tables resolve in place.

| | |
|---|---|
| **Files** | `lf_loot_table.gd`, `lf_loot_entry.gd` |
| **Tests** | `tests/test_lf_loot_table.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFWeightedPick`, `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFLootTable` | Resource: create it in the FileSystem dock, or with `.new()` |
| `LFLootEntry` | Resource: create it in the FileSystem dock, or with `.new()` |

## When to use it

Use it for drops: an enemy that drops gold 60 % of the time, a potion 30 %, and a roll on
the rare table 10 % — and maybe nothing at all. Each entry carries whatever you want back
(`content`), weights are relative, and an entry can point at another table (a "rare"
entry that rolls the rare table). Tables are Resources, so designers can author them as
`.tres` files in the Inspector. For a bare "pick an index by weight" use `LFWeightedPick`;
for "roll a rarity, then any item of it" over a big item pool, use `LFTierRoller`; for
bad-luck protection, add `LFPityTracker`.

## Step by step

1. In the Godot editor choose *Scene → New Scene*. In the *Scene* dock (top left) click **Other Node**, pick **Node**, and press *Create*.
2. With that node selected, click the *Attach Script* button (the scroll icon at the top of the *Scene* dock) and press *Create*. The script editor opens.
3. Replace everything in the script with the code below (the `#` text after a line is a comment: a note for you that Godot ignores):

   ```gdscript
   extends Node


   func _ready() -> void:
   	var rng := LFRandom.new(1)

   	# Gold (weight 60), a potion (30) and nothing at all (nothing_weight 10).
   	var drops := LFLootTable.new([
   		LFLootEntry.new("gold", 60.0),
   		LFLootEntry.new("potion", 30.0),
   	], 10.0)

   	for i in 8:
   		var drop := drops.roll(rng)          # an LFLootEntry, or null for "nothing"
   		if drop == null:
   			print("nothing")
   		else:
   			print(drop.content)
   ```
4. Change the entries: `LFLootEntry.new(what_you_get, weight)`. What you get can be anything (a name, a number, a scene). Weights are shares, so entries of `60` and `30` with a nothing-weight of `10` give 60 % gold, 30 % potion, 10 % nothing. In `LFLootTable.new([...], 10.0)` the `[...]` is the list of entries and `10.0` is the share of "nothing" (leave it out for a table that always drops something).
5. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: save it anywhere, for example as `test.tscn`. A game window may open and stay empty; that is fine. Close it when you are done.
6. In the *Output* panel you should see eight lines, each `gold`, `potion` or `nothing`, mostly gold. The seed `1` makes the list the same on every run. With only eight rolls, `nothing` may not appear; roll more times to see it.

### Or build the table in the editor

1. In the *FileSystem* dock (bottom left), right-click a folder (make one named `loot` first with *New Folder...*) and choose *New Resource...*.
2. Type `LFLootTable` in the search box, select it, press *Create*, and save it as `goblin.tres`.
3. Double-click `goblin.tres`. Its properties open in the *Inspector* (right side). Click **Entries** to expand it, set the size to 2, click the first `<empty>` slot and choose *New LFLootEntry*, then click the new entry to open it. Set **Id** to `gold` and **Weight** to `60`. Do the same for the second slot with **Id** `potion` and **Weight** `30`. Set **Nothing Weight** to `10`. Save with *Ctrl+S*.
4. To make an entry roll a whole other table instead, set its **Subtable** to another `.tres` made the same way.
5. Replace the script's contents with the code below. The editor cannot show an entry's `content` (it can hold any kind of value), so the code reads the **Id** you typed:

   ```gdscript
   extends Node


   func _ready() -> void:
   	var table: LFLootTable = load("res://loot/goblin.tres")   # the file you saved in the editor
   	var rng := LFRandom.new()

   	for i in 8:
   		var drop := table.roll(rng)          # an LFLootEntry, or null for "nothing"
   		if drop == null:
   			print("nothing")
   		else:
   			print(drop.id)                   # the name you typed into "Id" in the Inspector
   ```

6. If you saved the file somewhere else, change the path in `load(...)` (right-click the file in the *FileSystem* dock and choose *Copy Path*). Press **F6**: the *Output* panel shows eight lines, each `gold`, `potion` or `nothing`.


## API

Everything the class offers; you only need the rows used above to get started. `Variant` in a signature means "any kind of value".

### LFLootEntry

| Member | Signature | Description |
|---|---|---|
| `id` | `@export var id: StringName = &""` | An optional name to find and reconfigure an entry. |
| `DEFAULT_WEIGHT` | `const DEFAULT_WEIGHT := 1.0` | The weight an entry gets when none is given. |
| `weight` | `@export var weight: float = DEFAULT_WEIGHT` (1.0) | Relative; zero or less, NaN or `INF` is never chosen. |
| `subtable` | `@export var subtable: LFLootTable` | Rolled instead when set. |
| `content` | `@export_storage var content: Variant` | The payload you get back. |
| `_init` | `LFLootEntry.new(initial_content: Variant = null, initial_weight := DEFAULT_WEIGHT, initial_id: StringName = &"")` | An entry returning `initial_content`. |
| `nested` | `static nested(table: LFLootTable, entry_weight := DEFAULT_WEIGHT, entry_id: StringName = &"") -> LFLootEntry` | An entry that rolls `table`. |

### LFLootTable

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFLootTable.new(initial_entries: Array[LFLootEntry] = [], initial_nothing_weight := 0.0)` | Uses `initial_entries` as is (not copied). |
| `entries` | `@export var entries: Array[LFLootEntry] = []` | The possible drops; their order is band order for `pick_index`. |
| `nothing_weight` | `@export var nothing_weight: float = 0.0` | The "nothing" share, in entry units; its band is last. |
| `roll` | `roll(rng: RandomNumberGenerator, accept := Callable()) -> LFLootEntry` | An entry (through nested tables) or null. One `randf()` per level. `rng` is required (any `RandomNumberGenerator`, `LFRandom` included): null is reported and returns null. With `accept(entry) -> bool`, lands only on accepted entries (those without a `subtable`), never on nothing; see "Guaranteed drops". |
| `pick_index` | `pick_index(roll_value: float) -> int` | Pure top-level pick for a roll in [0, 1]; -1 for nothing. |
| `total_weight` | `total_weight() -> float` | Every positive finite entry weight plus a positive finite nothing weight; `INF` if that sum overflows (weights near 1e308), where rolls and chances still work. |
| `chance_of` | `chance_of(index: int) -> float` | Top-level share (0–1) of the entry at `index`; 0 out of range. |
| `nothing_chance` | `nothing_chance() -> float` | Top-level share of nothing; 1 when no weight is positive. |
| `find` | `find(id: StringName) -> LFLootEntry` | First top-level entry with `id`, or null. |
| `MAX_DEPTH` | `const MAX_DEPTH := 32` | Nesting followed before a roll gives up (reported). |

## Usage

```gdscript
# A script on an enemy.
extends Node

var rng := LFRandom.new()
var rare_table := LFLootTable.new([
	LFLootEntry.new("ring", 3.0),
	LFLootEntry.new("crown", 1.0),
])
var drops := LFLootTable.new([
	LFLootEntry.new("gold", 60.0),
	LFLootEntry.new("potion", 30.0),
	LFLootEntry.nested(rare_table, 10.0, &"rare"),   # 10 %: roll the rare table instead
], 100.0)                                           # nothing_weight 100: empty half the time


func _ready() -> void:
	print("chance of nothing: ", drops.nothing_chance())   # 0.5
	die()


func die() -> void:
	var drop := drops.roll(rng)
	if drop != null:
		print("dropped ", drop.content)
	else:
		print("dropped nothing")


func boost_rare_drops(percent: float) -> void:
	# Weights are read at roll time: change one and the next roll uses it.
	drops.find(&"rare").weight = 10.0 * (1.0 + percent / 100.0)
```

A table authored in the editor (see "Or build the table in the editor" above) can be loaded with `preload`, which reads the file when the script loads:
`var drops: LFLootTable = preload("res://loot/goblin.tres")`.
Entries made in the editor have no `content` field there (it can hold any value), so
use their `id` as the payload, or set `content` in code.

## Guaranteed drops

`roll(rng, accept)` rolls the same table but lands only on entries for which
`accept(entry)` returns `true`, never on nothing. The accepted entries keep the odds they
have against each other in a normal roll; a nested entry counts with the accepted share
of its table. It returns null only when no entry with a positive weight is accepted. Pair
it with `LFPityTracker` for bad-luck protection, with no second table:

```gdscript
# A goblin drop. After 3 drops in a row without a gem, the next drop is a gem.
extends Node

var rng := LFRandom.new()
var pity := LFPityTracker.new(3, 1)   # 3 misses in a row below tier 1 turn it on
var loot := LFLootTable.new([
	LFLootEntry.new({"name": "coin", "tier": 0}, 70.0),
	LFLootEntry.new({"name": "gem", "tier": 1}, 5.0),
], 25.0)                              # nothing 25 % of the time


func drop_loot() -> LFLootEntry:
	var drop: LFLootEntry
	if pity.is_active():
		drop = loot.roll(rng, _good_enough)   # never nothing, never below tier 1
	else:
		drop = loot.roll(rng)
	if drop == null:
		pity.record_outcome(false)            # nothing counts as a miss
	else:
		pity.record(drop.content.tier)        # tier 1 or more resets the streak
	return drop


func _good_enough(entry: LFLootEntry) -> bool:
	return entry.content.tier >= pity.threshold
```

`accept` may be called more than once per entry in one roll: keep it free of side effects.

## Notes

- Weights are relative and read at roll time; there is no luck setting — scale the
  weights yourself. A higher weight never means fewer drops.
- Think of the entries as consecutive slices of a 0-to-1 line, in the order listed, with the "nothing" slice last. A roll of exactly 1 lands on nothing
  when it has weight, else on the last entry that can drop.
- A roll without `accept` creates no arrays, dictionaries or objects of its own (an error
  report aside); it walks the entries of each table it visits at most twice (once to total
  the weights, once to find the band). A roll with `accept` builds one small array per
  table level and walks every nested table below each level it visits, to weigh it.
- In a roll with `accept`, a nested table that contains itself (directly or through other
  tables), or sits more than `MAX_DEPTH` levels down, is left out; this is reported once
  per roll.
- The unfiltered pick is `LFWeightedPick.index_by` over the entries with the nothing
  share as the last slice.
- `find` returns the first entry with the id, at the top level only (not inside nested
  tables).
- Tables and entries are Resources: author them as `.tres`. `content` is saved when it is
  a saveable value.
- For "roll a rarity, then an item of it", see `LFTierRoller`; for bad-luck protection,
  `LFPityTracker` with a filtered roll (see "Guaranteed drops").
