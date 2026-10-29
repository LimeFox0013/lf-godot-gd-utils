## Picks a random item in two steps: first a tier (a quality band) by weight, then an item of that tier.
##
## Tiers are ints from 0 up (e.g. 0 low, 1 mid, 2 high), and each tier has a relative
## weight. You may set a minimum tier (a "floor"): tiers below it are never rolled. When
## the rolled tier has no items, the nearest tier that has some is used instead (the
## [enum Fallback] direction first); when nothing at or above the floor has items, the
## floor is dropped rather than returning nothing. `pick` draws two numbers from your
## generator; `pick_from_buckets` takes the two rolls as arguments instead. Static: call
## it on the class, never `.new()` it.
class_name LFTierRoller

static var _log := LFLogger.new()


## Where to look when the rolled tier has no items.
enum Fallback {
	## Search toward the floor first, then upward.
	LOWER_FIRST,
	## Search upward first, then toward the floor.
	HIGHER_FIRST,
}


## Groups `items` by tier: returns `tier_count` arrays, where array `t` holds every item
## whose `tier_of(item) -> int` is `t`, in their original order. An item whose tier is
## outside 0..`tier_count - 1` is skipped and reported as an error.
static func bucket(items: Array, tier_of: Callable, tier_count: int) -> Array:
	var buckets := []
	for tier in tier_count:
		buckets.append([])
	for item: Variant in items:
		var tier: int = tier_of.call(item)
		if tier < 0 or tier >= tier_count:
			_log.error("LFTierRoller: an item's tier %d is outside 0..%d" % [tier, tier_count - 1])
			continue
		buckets[tier].append(item)
	return buckets


## The item two rolls choose from already-grouped items (see `bucket`), or null when
## every bucket is empty. `tier_roll` picks the tier and `item_roll` the item inside it
## (each from 0 to 1, e.g. `rng.randf()`). `weights[tier]` is each tier's relative
## weight. Tiers below `floor_tier` are never rolled (unless none at or above it has
## items, when the floor is dropped); a negative `floor_tier` counts as 0. With more
## weights than buckets, a roll landing past the last bucket counts as the last bucket.
static func pick_from_buckets(buckets: Array, weights: Array, tier_roll: float, item_roll: float, floor_tier: int = 0, fallback: Fallback = Fallback.LOWER_FIRST) -> Variant:
	var lowest := maxi(floor_tier, 0)
	var stocked_above := false
	for tier in range(lowest, buckets.size()):
		if !buckets[tier].is_empty():
			stocked_above = true
			break
	if !stocked_above:
		lowest = 0
	var rolled := LFWeightedPick.index(weights, tier_roll, lowest)
	if rolled == -1:
		rolled = lowest
	var tier := resolve_tier(buckets, rolled, lowest, fallback)
	if tier == -1:
		return null
	var items: Array = buckets[tier]
	return items[clampi(int(item_roll * items.size()), 0, items.size() - 1)]


## A random item of `items`: draws the tier roll, then the item roll, from `rng` and picks
## (see `pick_from_buckets` for the rules). `tier_of(item) -> int` gives an item's tier,
## and `weights.size()` sets how many tiers there are. Returns null, without drawing, when
## `items` is empty; a null `rng` is reported as an error and picks nothing. Groups
## `items` again on every call; on a hot path, `bucket` once and call `pick_from_buckets`.
static func pick(items: Array, tier_of: Callable, weights: Array, rng: RandomNumberGenerator, floor_tier: int = 0, fallback: Fallback = Fallback.LOWER_FIRST) -> Variant:
	if items.is_empty():
		return null
	if rng == null:
		_log.error("LFTierRoller.pick: picking needs a generator")
		return null
	var buckets := bucket(items, tier_of, weights.size())
	var tier_roll := rng.randf()
	var item_roll := rng.randf()
	return pick_from_buckets(buckets, weights, tier_roll, item_roll, floor_tier, fallback)


## The tier that actually gets used when `rolled` was rolled ("stocked" = has items):
## `rolled` itself when it has items, else the nearest stocked tier in the `fallback`
## direction first (never below `floor_tier`), then the other way. `rolled` is clamped
## into the buckets and a negative `floor_tier` counts as 0. Returns -1 when every
## bucket is empty.
static func resolve_tier(buckets: Array, rolled: int, floor_tier: int, fallback: Fallback = Fallback.LOWER_FIRST) -> int:
	if buckets.is_empty():
		return -1
	var lowest := clampi(floor_tier, 0, buckets.size() - 1)
	rolled = clampi(rolled, 0, buckets.size() - 1)
	if !buckets[rolled].is_empty():
		return rolled
	var first := _stocked_below(buckets, rolled, lowest) if fallback == Fallback.LOWER_FIRST else _stocked_above(buckets, rolled)
	if first != -1:
		return first
	return _stocked_above(buckets, rolled) if fallback == Fallback.LOWER_FIRST else _stocked_below(buckets, rolled, lowest)


## `base` weights with `shift` points moved out of the first tier (never taking it below
## `floor_of_first`) and spread over the others in proportion to their base weights, so a
## bonus such as luck raises the rarer tiers. Returns a new array; `base` is not changed.
## A negative `shift` counts as 0; with no other tier or no weight to spread, nothing moves.
static func tilt_weights(base: Array, shift: float, floor_of_first: float) -> Array[float]:
	var weights: Array[float] = []
	for weight: Variant in base:
		weights.append(float(weight))
	if weights.size() < 2:
		return weights
	var max_shift := maxf(float(base[0]) - floor_of_first, 0.0)
	var moved := clampf(shift, 0.0, max_shift)
	var higher_total := 0.0
	for tier in range(1, base.size()):
		higher_total += float(base[tier])
	if higher_total <= 0.0:
		return weights
	weights[0] -= moved
	for tier in range(1, base.size()):
		weights[tier] += moved * float(base[tier]) / higher_total
	return weights


static func _stocked_below(buckets: Array, rolled: int, lowest: int) -> int:
	for tier in range(rolled - 1, lowest - 1, -1):
		if !buckets[tier].is_empty():
			return tier
	return -1


static func _stocked_above(buckets: Array, rolled: int) -> int:
	for tier in range(rolled + 1, buckets.size()):
		if !buckets[tier].is_empty():
			return tier
	return -1
