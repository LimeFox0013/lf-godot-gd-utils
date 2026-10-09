## A loot table: a list of possible drops with weights, plus an optional chance of dropping nothing.
##
## Each [LFLootEntry] is chosen in proportion to its weight over the total (entries plus
## `nothing_weight`); an entry holding a nested table resolves through it, so a roll
## always ends at an entry or nothing. Weights are relative (60 and 30 is the same as 2
## and 1) and read at roll time — change a weight and roll again, no rebuilding. There is
## no luck setting: scale the weights yourself. Rolling draws one `randf()` per table
## level visited, from your generator; an unfiltered roll creates no arrays, dictionaries
## or objects of its own (an error report aside). A filtered roll (`roll(rng, accept)`)
## lands only on the entries you accept, for a guaranteed drop such as bad-luck
## protection. It is a Resource, so tables can be authored as `.tres` files in the
## Inspector.
class_name LFLootTable
extends Resource

static var _log := LFLogger.new()


## How many nested tables a roll follows before it gives up, reports an error and returns
## nothing (protects against a table that contains itself).
const MAX_DEPTH := 32

## What weights are multiplied by (2^-64) to compute shares when their plain sum
## overflows the float range.
const _OVERFLOW_SCALE := 1.0 / 18446744073709551616.0

## The possible drops. Their order matters only for `pick_index` (earlier entries take
## the lower rolls).
@export var entries: Array[LFLootEntry] = []
## How likely a roll gives nothing, in the same units as the entry weights: entries
## weighing 60 + 30 with `nothing_weight` 90 drop nothing half the time. 0: always drops.
@export var nothing_weight: float = 0.0


## Band `i`'s weight for `LFWeightedPick.index_by`: entry `i`'s, then nothing's last.
## Bound once, so a roll creates no Callable.
var _weight_at := _band_weight


## A table over `initial_entries` (used as is, not copied) with an
## `initial_nothing_weight` share of nothing.
func _init(initial_entries: Array[LFLootEntry] = [], initial_nothing_weight := 0.0) -> void:
	entries = initial_entries
	nothing_weight = initial_nothing_weight


## Rolls the table with `rng` and returns the entry it lands on — through any nested
## tables — or null for nothing. Read the payload from the entry's `content`. A null `rng`
## is reported as an error and returns null.
##
## With `accept` (`func(entry: LFLootEntry) -> bool`), the roll lands only on entries
## without a `subtable` for which `accept` returns true, and never on nothing; each such
## entry keeps the odds it has relative to the other accepted entries in an unfiltered
## roll (a nested entry weighs in with the accepted share of its table). Null when no
## positively weighted entry is accepted. `accept` may be called more than once per entry
## in one roll, so keep it free of side effects. A filtered roll builds a small array per
## table level it visits; a table that contains itself is reported and that entry is
## left out.
func roll(rng: RandomNumberGenerator, accept := Callable()) -> LFLootEntry:
	if rng == null:
		_log.error("LFLootTable: rolling needs a generator")
		return null
	if accept.is_null():
		return _roll(rng, 0)
	var walk := {"path": [], "reported": false}
	return _roll_accepted(rng, accept, walk)


## The index in `entries` that `roll_value` (from 0 to 1) lands on, or -1 for nothing —
## at the top level only, without following nested tables, and without randomness of its
## own. The rolls are split into bands: one per entry in order (each band as wide as the
## entry's share), then the nothing band. A roll of 1 lands on nothing when it has weight,
## else on the last positively weighted entry.
func pick_index(roll_value: float) -> int:
	var index := LFWeightedPick.index_by(entries.size() + 1, _weight_at, roll_value)
	return -1 if index == entries.size() else index


## The sum of every positive finite entry weight plus a positive finite `nothing_weight`
## (top level only). An `INF` weight is never chosen, so it counts as 0 here too. `INF`
## when the sum itself overflows the float range (weights near 1e308); rolls and chances
## still work then.
func total_weight() -> float:
	return _scaled_total(1.0)


## The chance (0–1) that a roll picks `entries[index]` at the top level; 0 for an index
## out of range or an entry that can't be chosen.
func chance_of(index: int) -> float:
	var entry: LFLootEntry = entries[index] if index >= 0 and index < entries.size() else null
	if entry == null or !_chooses(entry.weight):
		return 0.0
	# A chosen weight is part of the total, so the total is positive too.
	var scale := _share_scale()
	return entry.weight * scale / _scaled_total(scale)


## The chance (0–1) that a roll at the top level gives nothing; 1 when no weight is
## positive.
func nothing_chance() -> float:
	var scale := _share_scale()
	var total := _scaled_total(scale)
	return (nothing_weight * scale if _chooses(nothing_weight) else 0.0) / total if total > 0.0 else 1.0


## The first top-level entry whose `id` is `id`, or null (nested tables are not searched).
func find(id: StringName) -> LFLootEntry:
	for entry in entries:
		if entry != null and entry.id == id:
			return entry
	return null


func _roll(rng: RandomNumberGenerator, depth: int) -> LFLootEntry:
	if depth > MAX_DEPTH:
		_log.error("LFLootTable: nested more than %d deep (a table containing itself?)" % MAX_DEPTH)
		return null
	var index := pick_index(rng.randf())
	if index == -1:
		return null
	var entry := entries[index]
	if entry.subtable != null:
		return entry.subtable._roll(rng, depth + 1)
	return entry


# One level of a filtered roll: picks among this table's entries by their accepted weight
# (nothing excluded), then follows a nested entry. `walk.path` holds the tables above.
func _roll_accepted(rng: RandomNumberGenerator, accept: Callable, walk: Dictionary) -> LFLootEntry:
	var path: Array = walk.path
	path.append(self)
	var weights := []
	for entry in entries:
		weights.append(_accepted_weight(entry, accept, walk))
	var index := LFWeightedPick.index(weights, rng.randf())
	var picked: LFLootEntry = entries[index] if index != -1 else null
	if picked != null and picked.subtable != null:
		picked = picked.subtable._roll_accepted(rng, accept, walk)
	path.pop_back()
	return picked


# `entry`'s weight in a filtered roll: its own weight when accepted, a nested entry's
# weight times the accepted share of its table, else 0.
func _accepted_weight(entry: LFLootEntry, accept: Callable, walk: Dictionary) -> float:
	if entry == null or !_chooses(entry.weight):
		return 0.0
	if entry.subtable == null:
		var accepted: Variant = accept.call(entry)
		return entry.weight if accepted is bool and accepted else 0.0
	return entry.weight * entry.subtable._accepted_share(accept, walk)


# The share (0–1) of this table's total weight, nothing included, that a filtered roll
# accepts. 0 for a table already on the path (it contains itself) or nested past
# `MAX_DEPTH`, reported once per roll.
func _accepted_share(accept: Callable, walk: Dictionary) -> float:
	var path: Array = walk.path
	if path.has(self) or path.size() > MAX_DEPTH:
		if not walk.reported:
			walk.reported = true
			_log.error("LFLootTable: a filtered roll left out a nested table that contains itself or is nested more than %d deep" % MAX_DEPTH)
		return 0.0
	var scale := _share_scale()
	var total := _scaled_total(scale)
	if !(total > 0.0):
		return 0.0
	path.append(self)
	var accepted := 0.0
	for entry in entries:
		accepted += _accepted_weight(entry, accept, walk) * scale
	path.pop_back()
	return accepted / total


# The `total_weight` with every weight multiplied by `scale`.
func _scaled_total(scale: float) -> float:
	var total := nothing_weight * scale if _chooses(nothing_weight) else 0.0
	for entry in entries:
		if entry != null and _chooses(entry.weight):
			total += entry.weight * scale
	return total


# 1, or `_OVERFLOW_SCALE` when the plain sum of the weights overflows.
func _share_scale() -> float:
	return 1.0 if _scaled_total(1.0) < INF else _OVERFLOW_SCALE


# Whether a weight can be chosen: positive and finite, as `LFWeightedPick` reads it.
static func _chooses(weight: float) -> bool:
	return weight > 0.0 and weight < INF


func _band_weight(i: int) -> float:
	if i < entries.size():
		var entry := entries[i]
		return entry.weight if entry != null else 0.0
	return nothing_weight
