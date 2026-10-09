## Picks an index at random where some indices are more likely than others (a weighted pick).
##
## With weights `[60, 30, 10]`, index 0 comes up 60 % of the time, index 1 30 % and
## index 2 10 %. You pass the random roll in (a number from 0 to 1, e.g. `rng.randf()`),
## so you decide where randomness comes from — a seeded `LFRandom` for replayable picks, or
## a fixed number in a test. The pick itself has no side effects. Static: call it on the
## class, never `.new()` it.
class_name LFWeightedPick

## What the weights' running total and scale are multiplied by (2^-64) when the next
## weight would push the total past the float range. A power of two, so the scaled shares
## stay exact, except that once scaled, weights below about 1e-289 lose precision and
## weights below about 1e-305 count as 0.
const _OVERFLOW_SCALE := 1.0 / 18446744073709551616.0


## The index chosen by `roll` over `weights`, considering only indices from `from` on (a
## negative `from` counts from 0); each index's chance is its weight over the considered
## total. An index whose weight is zero, negative, NaN or `INF` is never chosen and doesn't
## change the total. `roll` is meant to be in [0, 1): one at or below 0 picks the first
## positively weighted index, and one at or above 1 (`randf()` can return 1.0) or NaN picks
## the last.
## Returns -1 when nothing can be chosen: no weights, `from` at or past the end, or no
## positive weight from `from` on. Finite weights whose total is past the float range
## (`[1e308, 1e308]`) still pick by share: they are scaled down while summing.
static func index(weights: Array, roll: float, from := 0) -> int:
	# The same walk as `index_by`, written out: reading the array directly skips a
	# Callable call per weight.
	from = maxi(from, 0)
	var total := 0.0
	var scale := 1.0
	var last_positive := -1
	for i in range(from, weights.size()):
		var weight: float = weights[i]
		if weight > 0.0 and weight < INF:
			if is_inf(total + weight * scale):
				total *= _OVERFLOW_SCALE
				scale *= _OVERFLOW_SCALE
			total += weight * scale
			last_positive = i
	if last_positive == -1:
		return -1
	var target := roll * total
	var cumulative := 0.0
	for i in range(from, last_positive):
		var weight: float = weights[i]
		if weight > 0.0 and weight < INF:
			cumulative += weight * scale
			if target < cumulative:
				return i
	return last_positive


## `index`, with the weights read through `weight_at(i) -> float` for each `i` below
## `count` instead of from an array — for weights that live in other objects (a table's
## entries, a computed share). Same rules as `index`. `weight_at` is called twice per
## considered index at most; bind it once and reuse it rather than building a new lambda
## for every roll.
static func index_by(count: int, weight_at: Callable, roll: float, from := 0) -> int:
	from = maxi(from, 0)
	var total := 0.0
	var scale := 1.0
	var last_positive := -1
	for i in range(from, count):
		var weight: float = weight_at.call(i)
		if weight > 0.0 and weight < INF:
			if is_inf(total + weight * scale):
				total *= _OVERFLOW_SCALE
				scale *= _OVERFLOW_SCALE
			total += weight * scale
			last_positive = i
	if last_positive == -1:
		return -1
	var target := roll * total
	var cumulative := 0.0
	for i in range(from, last_positive):
		var weight: float = weight_at.call(i)
		if weight > 0.0 and weight < INF:
			cumulative += weight * scale
			if target < cumulative:
				return i
	return last_positive
