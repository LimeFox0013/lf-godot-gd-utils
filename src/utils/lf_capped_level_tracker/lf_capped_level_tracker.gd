## Counts levels per owner and per id (e.g. "owner A holds id x at level 2"), raised one at a time up to a cap.
##
## An owner is any key you choose — a user id, a node, a session. You pass the cap on every
## raise, and the check happens inside `try_raise()` itself, so a level can never go past
## the cap it was raised under. It stores only the levels: no caps, definitions or bonuses.
class_name LFCappedLevelTracker


## Emitted after every successful raise; `new_level` is `owner`'s level of `id` after it.
signal raised(owner: Variant, id: StringName, new_level: int)
## Emitted after `clear()`.
signal cleared
## Emitted after `forget(owner)` — even when `owner` held no level, so a listener can drop
## its own state for that owner.
signal forgotten(owner: Variant)

# owner -> { id: level }
var _levels: Dictionary = {}


## The level `owner` holds for `id`, or 0 if it was never raised. Reading creates no
## record.
func level_for(owner: Variant, id: StringName) -> int:
	var owner_levels: Variant = _levels.get(owner)
	return owner_levels.get(id, 0) if owner_levels != null else 0


## Whether one more raise of `owner`'s `id` would stay within `cap` (its level is below
## `cap`). Changes nothing.
func has_capacity(owner: Variant, id: StringName, cap: int) -> bool:
	return level_for(owner, id) < cap


## Raises `owner`'s `id` by one if that stays within `cap` and returns true (announcing
## `raised`); otherwise returns false and changes nothing. A cap of 0 or less always
## rejects; a lower cap than an earlier one never lowers the level.
func try_raise(owner: Variant, id: StringName, cap: int) -> bool:
	var owner_levels: Dictionary = _levels.get(owner, {})
	var level: int = owner_levels.get(id, 0)
	if level >= cap:
		return false
	if owner_levels.is_empty():
		_levels[owner] = owner_levels
	level += 1
	owner_levels[id] = level
	raised.emit(owner, id, level)
	return true


## Clears every level of every owner, then emits `cleared`.
func clear() -> void:
	_levels = {}
	cleared.emit()


## Drops every level `owner` holds (it reads as never raised again), then emits
## `forgotten`. Call it for owners that leave: an Object owner is otherwise kept alive
## until `clear()`.
func forget(owner: Variant) -> void:
	_levels.erase(owner)
	forgotten.emit(owner)
