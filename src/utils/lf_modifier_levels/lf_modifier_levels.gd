## Levels of modifiers (any id that grants stat bonuses per level) per owner, and the stat bonuses those levels add up to.
##
## Declare each modifier once with what one level adds per stat key (e.g. `mod_a` adds
## `{"stat_a": 2.0}` per level). Owners raise levels within a cap; read back a level, its
## worth for one key, or a whole group's totals as one Dictionary.
##
## - A **shared owner** (optional) holds levels that count for every owner — e.g. levels that
##   apply to everyone. A cap limits an owner's own levels only.
## - A per-owner **cap bonus** raises every cap for that owner, for the modifiers declared
##   to accept it.
## - **Groups** name who reads a modifier (e.g. `&"group_a"`, `&"group_b"`):
##   `bonuses_for(owner, group)` returns the summed worth of the group's modifiers as a
##   read-only Dictionary (a "snapshot"). The same Dictionary is returned until a level
##   feeding it changes, and one already handed out never changes.
##
## Levels live in an `LFCappedLevelTracker` (created, or passed in to share one). Override
## `_bonus_at()` in a subclass for curves or per-level tables.
class_name LFModifierLevels

static var _log := LFLogger.new()


## Emitted when `owner`'s own level of `id` went up to `new_level` (relayed from the
## tracker, so raises made directly on `tracker` count too).
signal raised(owner: Variant, id: StringName, new_level: int)

## The owner whose levels count for every owner (null: none). Read-only; set it in `new()`.
var shared_owner: Variant:
	get:
		return _shared_owner
## The level counter underneath (read-only). A raise made on it directly still renews
## snapshots.
var tracker: LFCappedLevelTracker:
	get:
		return _tracker

var _shared_owner: Variant
## `{shared owner: true}` (empty with none): `has()` matches an owner exactly as the
## tracker's Dictionary keys do (`"shared"` and `&"shared"` alike, `1` and `"1"` not).
var _shared_key: Dictionary = {}
var _tracker: LFCappedLevelTracker
## id -> { _KEY_BONUS: Dictionary, _KEY_GROUPS: Array[StringName], _KEY_CAP_BONUS: bool }, in declaration order.
var _declared: Dictionary = {}
## group -> Array[StringName] of its ids, in declaration order.
var _groups: Dictionary = {}
## owner -> extra cap.
var _cap_bonus: Dictionary = {}
## group -> { owner: read-only snapshot }.
var _snapshots: Dictionary = {}

const _NO_IDS: Array[StringName] = []
const _EMPTY := {}
## Keys of each `_declared` record: the per-level bonus, the groups, and whether the cap
## bonus applies.
const _KEY_BONUS := "bonus"
const _KEY_GROUPS := "groups"
const _KEY_CAP_BONUS := "cap_bonus"


## New levels. The levels of `initial_shared_owner` count for every owner (null: no shared
## owner). They are kept in `shared_tracker` (null: a new one; pass one to share levels
## with other users of it, such as an `LFModifierGrantService`).
func _init(initial_shared_owner: Variant = null, shared_tracker: LFCappedLevelTracker = null) -> void:
	_shared_owner = initial_shared_owner
	if initial_shared_owner != null:
		_shared_key[initial_shared_owner] = true
	_tracker = shared_tracker if shared_tracker != null else LFCappedLevelTracker.new()
	_tracker.raised.connect(_on_raised)
	_tracker.cleared.connect(_on_cleared)
	_tracker.forgotten.connect(_on_forgotten)


## Declares `id`: each of its levels adds `bonus_per_level[key]` to `key` (keys are any
## stat names, values numbers). `groups` name who reads it in `bonuses_for` (a group
## listed twice counts once). With `cap_bonus_applies` false, `id`'s cap is exactly what
## `grant()` is given. Returns true; declaring an id twice is reported as an error and
## returns false.
func declare(id: StringName, bonus_per_level: Dictionary = {}, groups: Array[StringName] = [], cap_bonus_applies := true) -> bool:
	if _declared.has(id):
		_log.error("LFModifierLevels: '%s' is already declared" % id)
		return false
	_declared[id] = {_KEY_BONUS: bonus_per_level.duplicate(), _KEY_GROUPS: groups.duplicate(), _KEY_CAP_BONUS: cap_bonus_applies}
	for group in groups:
		if !_groups.has(group):
			var ids: Array[StringName] = []
			_groups[group] = ids
		if _groups[group].has(id):
			continue
		_groups[group].append(id)
		_snapshots.erase(group)
	return true


## Whether `id` was declared with `declare`.
func is_declared(id: StringName) -> bool:
	return _declared.has(id)


## Every declared id, in declaration order (a new array).
func declared_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_declared.keys())
	return ids


## The ids declared in `group`, in declaration order (a new array; empty for an unknown
## group).
func ids_in(group: StringName) -> Array[StringName]:
	return _groups.get(group, _NO_IDS).duplicate()


## Raises `owner`'s own level of `id` by one, up to `effective_cap(owner, id, cap)`, and
## returns true (emitting `raised`). Returns false at the cap, or when `id` isn't
## declared (reported as an error).
func grant(owner: Variant, id: StringName, cap: int) -> bool:
	if !_check_declared(id):
		return false
	return _tracker.try_raise(owner, id, effective_cap(owner, id, cap))


## Whether `owner` could be granted one more level of `id` under `cap` (plus its cap
## bonus, when `id` accepts it). Changes nothing.
func has_capacity(owner: Variant, id: StringName, cap: int) -> bool:
	return _tracker.has_capacity(owner, id, effective_cap(owner, id, cap))


## The real cap of `owner`'s `id`: `cap`, plus `owner`'s cap bonus when `id` accepts it
## (just `cap` for an undeclared id).
func effective_cap(owner: Variant, id: StringName, cap: int) -> int:
	var declared: Variant = _declared.get(id)
	if declared != null and declared[_KEY_CAP_BONUS]:
		return cap + cap_bonus_of(owner)
	return cap


## Raises every cap of `owner` by `amount` (on top of earlier bonuses), for the ids that
## accept a cap bonus. A negative `amount` lowers it again.
func add_cap_bonus(owner: Variant, amount: int) -> void:
	_cap_bonus[owner] = cap_bonus_of(owner) + amount


## `owner`'s cap bonus (the sum of what `add_cap_bonus` added; 0 if none), whatever the id.
func cap_bonus_of(owner: Variant) -> int:
	return _cap_bonus.get(owner, 0)


## `owner`'s cap bonus for `id`: `cap_bonus_of(owner)` when `id` accepts a cap bonus, else
## 0 (also for an undeclared id). Shaped for `LFModifierGrantService`'s `cap_bonus_of`, so
## a grant service over this `tracker` honours the per-id rule.
func cap_bonus_for(owner: Variant, id: StringName) -> int:
	var declared: Variant = _declared.get(id)
	return cap_bonus_of(owner) if declared != null and declared[_KEY_CAP_BONUS] else 0


## `owner`'s own level of `id` — without the shared owner's; 0 if never granted.
func own_level(owner: Variant, id: StringName) -> int:
	return _tracker.level_for(owner, id)


## `owner`'s level of `id`: its own plus the shared owner's (counted once for the shared
## owner itself); 0 if neither holds any.
func level_of(owner: Variant, id: StringName) -> int:
	var level := _tracker.level_for(owner, id)
	if !_shared_key.is_empty() and !_is_shared(owner):
		level += _tracker.level_for(_shared_owner, id)
	return level


## What `owner`'s levels of `id` add to `key` (0.0 when it adds nothing to it). An
## undeclared `id` is reported as an error and returns 0.0.
func bonus_of(owner: Variant, id: StringName, key: Variant) -> float:
	if !_check_declared(id):
		return 0.0
	return _bonus_at(id, key, level_of(owner, id))


## What every modifier in `group` adds to `key` for `owner`, summed (0.0 for an unknown
## group). Recomputed on every call; `bonuses_for` caches.
func total_of(owner: Variant, key: Variant, group: StringName) -> float:
	var total := 0.0
	for id: Variant in _groups.get(group, _NO_IDS):
		var level := level_of(owner, id)
		if level > 0 and _declared[id][_KEY_BONUS].has(key):
			total += _bonus_at(id, key, level)
	return total


## `{key: total}` over every modifier in `group` that `owner` holds a level of (empty when
## none). Read-only and shared: the same Dictionary comes back until a level feeding it
## changes, then a new one is built. One already handed out never changes.
func bonuses_for(owner: Variant, group: StringName) -> Dictionary:
	var by_owner: Dictionary = _snapshots.get(group, _EMPTY)
	var snapshot: Variant = by_owner.get(owner)
	if snapshot != null:
		return snapshot
	var built := {}
	for id: Variant in _groups.get(group, _NO_IDS):
		var level := level_of(owner, id)
		if level <= 0:
			continue
		for key: Variant in _declared[id][_KEY_BONUS]:
			built[key] = built.get(key, 0.0) + _bonus_at(id, key, level)
	built.make_read_only()
	if by_owner.is_read_only():
		by_owner = {}
		_snapshots[group] = by_owner
	by_owner[owner] = built
	return built


## Clears every level and cap bonus of every owner; declarations stay. The levels are
## cleared in the tracker, so on a shared tracker every user of it loses them too (other
## `LFModifierLevels` on it keep their own cap bonuses).
func clear() -> void:
	_cap_bonus.clear()
	_tracker.clear()


## Drops everything held for `owner` — its levels (through the tracker, which announces
## `forgotten` to everyone sharing it), its cap bonus and its snapshots. Forgetting the
## shared owner renews every owner's snapshots.
func forget(owner: Variant) -> void:
	_tracker.forget(owner)


## What `level` levels of `id` add to `key`: by default level × its declared amount.
## Override for curves or per-level tables. `bonus_of` asks it about any key;
## `total_of` and `bonuses_for` only about the keys `id` declared in `bonus_per_level`.
## Snapshots are renewed only when a level changes, so an override must not read state
## that changes on its own.
func _bonus_at(id: StringName, key: Variant, level: int) -> float:
	return level * float(_declared[id][_KEY_BONUS].get(key, 0.0))


func _check_declared(id: StringName) -> bool:
	if _declared.has(id):
		return true
	_log.error("LFModifierLevels: '%s' is not declared" % id)
	return false


func _is_shared(owner: Variant) -> bool:
	return _shared_key.has(owner)


func _on_raised(owner: Variant, id: StringName, new_level: int) -> void:
	var declared: Variant = _declared.get(id)
	if declared != null:
		for group: Variant in declared[_KEY_GROUPS]:
			if _is_shared(owner):
				_snapshots.erase(group)
			elif _snapshots.has(group):
				_snapshots[group].erase(owner)
	raised.emit(owner, id, new_level)


func _on_cleared() -> void:
	_snapshots.clear()


func _on_forgotten(owner: Variant) -> void:
	_cap_bonus.erase(owner)
	if _is_shared(owner):
		_snapshots.clear()
		return
	for group: Variant in _snapshots:
		_snapshots[group].erase(owner)
