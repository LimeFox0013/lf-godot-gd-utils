## A random number generator you can seed, with the rolls needed most: chance, pick, shuffle.
##
## Give one `LFRandom` to a system (a simulation, an AI, procedural generation) and the same seed replays
## exactly the same rolls — handy for replays, shared seeds and tests. It extends
## [RandomNumberGenerator], so it also has everything a plain generator has (`seed`,
## `state`, `randf()`, `randi_range()` ...). For directions and points on the XZ plane,
## pass it to `LFUtils3D.random_direction_xz` / `random_point_in_circle_xz`.
##
## It never touches Godot's global generator (the one behind the global `randf()`).
## Rolls inside this class go through `self.` — a bare `randf()` or `randomize()` here
## would call GDScript's global function instead.
class_name LFRandom
extends RandomNumberGenerator


## How many unseeded sources this process has made — mixed into each one's seed.
static var _unseeded := 0


## Seeds from `seed_value`, an int (any int, -1 included). Without one (null), seeds
## randomly: from the clock (the engine's own randomize) mixed with a per-process counter,
## so two sources made in the same microsecond still differ.
func _init(seed_value: Variant = null) -> void:
	if seed_value != null:
		seed = seed_value
		return
	_unseeded += 1
	self.randomize()
	seed = hash([seed, _unseeded])


## True with probability `fraction` (0–1). At or above 1 always, at or below 0 or NaN
## never — neither consumes a roll; anything else consumes exactly one `randf()`.
func chance(fraction: float) -> bool:
	if fraction >= 1.0:
		return true
	if !(fraction > 0.0):
		return false
	return self.randf() < fraction


## A random element of `items`, each equally likely. Returns null (without a roll) when
## `items` is empty.
func pick(items: Array) -> Variant:
	return items[self.randi_range(0, items.size() - 1)] if !items.is_empty() else null


## Puts `items` in a random order, in place (the array you pass is changed). Every order
## is equally likely (the Fisher–Yates method). Empty and one-item arrays are left as they are.
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := self.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
