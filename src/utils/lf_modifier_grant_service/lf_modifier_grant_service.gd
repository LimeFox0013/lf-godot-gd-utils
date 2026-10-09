## Gives an id (anything you count per owner) to an owner up to a capped count, and decides what happens at the cap.
##
## At the cap you choose: a hard stop (nothing changes), or a conversion (an action of
## yours runs instead — e.g. a duplicate turns into a refund — and the count stays). Counts
## live in an `LFCappedLevelTracker`, created for you or passed in so several services
## (two sources of the same ids) share one cap. It handles no costs: paying,
## refunding and what a grant does are yours, through `on_grant` / `on_overflow`.
class_name LFModifierGrantService


## What `grant` did.
enum Outcome {
	## Below the cap: the grant was counted and `on_grant` ran.
	GRANTED,
	## At the cap with no `on_overflow`: nothing changed.
	REJECTED,
	## At the cap: `on_overflow` ran instead; the count is unchanged.
	CONVERTED,
}

## Emitted after a counted grant (and its `on_grant`); `count` is the owner's count of
## `id` now.
signal granted(owner: Variant, id: StringName, count: int)
## Emitted at the cap when there is no `on_overflow`: nothing changed.
signal rejected(owner: Variant, id: StringName)
## Emitted at the cap after `on_overflow` ran instead; the count is unchanged.
signal converted(owner: Variant, id: StringName)

## The counter underneath (read-only). Pass it to another service or an
## `LFModifierLevels` to share the same counts.
var tracker: LFCappedLevelTracker:
	get:
		return _tracker

var _tracker: LFCappedLevelTracker
var _cap_bonus_of: Callable
## Whether `_cap_bonus_of` takes the id as well as the owner.
var _bonus_per_id := false

## How many arguments a per-id `cap_bonus_of` takes: `(owner, id)`.
const _PER_ID_ARG_COUNT := 2


## Counts in `shared_tracker`, or in a new tracker when it is null. `cap_bonus_of` raises
## caps: `(owner, id) -> int` for a bonus that depends on the id
## (`LFModifierLevels.cap_bonus_for` fits), or `(owner) -> int` for one bonus on every id.
## It is called at every check, so it may read state that changes over time. Without it
## the bonus is 0.
func _init(shared_tracker: LFCappedLevelTracker = null, cap_bonus_of := Callable()) -> void:
	_tracker = shared_tracker if shared_tracker != null else LFCappedLevelTracker.new()
	_cap_bonus_of = cap_bonus_of
	_bonus_per_id = cap_bonus_of.is_valid() and cap_bonus_of.get_argument_count() >= _PER_ID_ARG_COUNT


## How many times `id` was granted to `owner` (0 if never). Conversions don't count.
func count_for(owner: Variant, id: StringName) -> int:
	return _tracker.level_for(owner, id)


## The real cap: `cap` plus `owner`'s cap bonus (for `id`, when the bonus depends on the
## id). Pass `&""` for a bonus that does not depend on the id. Just `cap` without a
## bonus callback.
func effective_cap(owner: Variant, id: StringName, cap: int) -> int:
	if !_cap_bonus_of.is_valid():
		return cap
	return cap + int(_cap_bonus_of.call(owner, id) if _bonus_per_id else _cap_bonus_of.call(owner))


## Whether one more grant of `id` to `owner` stays within `cap` plus its cap bonus.
## Changes nothing.
func has_capacity(owner: Variant, id: StringName, cap: int) -> bool:
	return _tracker.has_capacity(owner, id, effective_cap(owner, id, cap))


## Tries to grant `id` to `owner` under `cap` (plus the cap bonus) and returns what
## happened. Below the cap: counts the grant, runs `on_grant()`, emits `granted` →
## GRANTED. At the cap with no `on_overflow`: emits `rejected`, changes nothing →
## REJECTED. At the cap otherwise: runs `on_overflow()`, emits `converted` → CONVERTED.
## Both callbacks take no arguments (use `bind` to pass some). The check and the count
## are one step, so they can never disagree.
func grant(owner: Variant, id: StringName, cap: int, on_grant := Callable(), on_overflow := Callable()) -> Outcome:
	if _tracker.try_raise(owner, id, effective_cap(owner, id, cap)):
		if on_grant.is_valid():
			on_grant.call()
		granted.emit(owner, id, _tracker.level_for(owner, id))
		return Outcome.GRANTED
	if !on_overflow.is_valid():
		rejected.emit(owner, id)
		return Outcome.REJECTED
	on_overflow.call()
	converted.emit(owner, id)
	return Outcome.CONVERTED


## Forgets every grant to every owner (the tracker emits `cleared`).
func clear() -> void:
	_tracker.clear()


## Forgets every grant to `owner` — for an owner that leaves. Goes through the tracker,
## which emits `forgotten` to everyone sharing it.
func forget(owner: Variant) -> void:
	_tracker.forget(owner)
