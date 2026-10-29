## An experience track: gain experience, level up when a level's threshold is reached, and carry
## the left-over experience into the next levels.
##
## You give it the experience each level step needs (`[10, 20, 40]`: 10 to go from level 0 to
## 1, 20 from 1 to 2, 40 from 2 to 3). `gain(amount)` adds experience, raises the level as many
## times as the amount pays for and keeps the remainder as progress toward the next level.
## It stores only the level and the experience inside it, so what a level is worth (damage,
## health, a skill choice) stays in your game: look it up by `level`. Levels start at 0 and
## the highest is `max_level`, the number of thresholds.
class_name LFExperienceLevels
extends RefCounted


## Emitted once for every level gained, with the level reached. `gain(35)` over thresholds
## `[10, 20, 40]` emits it for level 1 and then for level 2. `set_level` and `reset` do not
## emit it.
signal leveled_up(new_level: int)
## Emitted at the end of every accepted `gain` with the amount given, after any `leveled_up`.
## Not emitted when the track is already at its top level.
signal experience_gained(amount: float)

## The level now, from 0 to `max_level`. Change it with `gain`, `set_level` or `reset`.
var level: int = 0
## The experience held toward the next level: below that level's threshold, and 0 at the top
## level.
var experience: float = 0.0
## The highest level: the number of thresholds given.
var max_level: int:
	get:
		return _thresholds.size()

var _thresholds: PackedFloat64Array = PackedFloat64Array()
var _log := LFLogger.new(['LFExperienceLevels'])


## A track whose level steps need the given `thresholds` (numbers of 0 or more), starting at
## `start_level` with no experience. A threshold that is negative, not finite or not a number
## is reported through `LFLogger` and counts as 0; a `start_level` outside 0 to `max_level` is
## reported and the track starts at level 0.
func _init(thresholds: Array = [], start_level: int = 0) -> void:
	set_thresholds(thresholds, start_level)


## Replaces the thresholds (as in `_init`), sets the level to `start_level` and drops the
## experience. Emits no signal.
func set_thresholds(thresholds: Array, start_level: int = 0) -> void:
	_thresholds = PackedFloat64Array()
	for threshold: Variant in thresholds:
		_thresholds.append(_checked_threshold(threshold))
	level = 0
	experience = 0.0
	set_level(start_level)


## The thresholds, one per level step, as a copy.
func get_thresholds() -> PackedFloat64Array:
	return _thresholds.duplicate()


## Whether the track is at its top level (also true for a track with no thresholds).
func is_max() -> bool:
	return level >= max_level


## The experience needed to go from the current level to the next, or `INF` at the top level.
func next_threshold() -> float:
	if is_max():
		return INF
	return _thresholds[level]


## How far through the current level, from 0.0 to 1.0. 1.0 at the top level and when the next
## level step needs 0.
func progress() -> float:
	if is_max():
		return 1.0
	var threshold: float = _thresholds[level]
	if threshold <= 0.0:
		return 1.0
	return clampf(experience / threshold, 0.0, 1.0)


## Adds `amount` experience and returns how many levels it gained. Left-over experience carries
## into the next level, so one big amount can raise several levels (each emits `leveled_up`);
## experience beyond the top level is dropped. An `amount` that is negative or not finite is
## reported through `LFLogger` and ignored. At the top level it does nothing and returns 0.
func gain(amount: float) -> int:
	if not is_finite(amount) or amount < 0.0:
		_log.error('gain needs a finite amount of 0 or more, got', amount)
		return 0
	if is_max():
		return 0
	experience += amount
	var gained := 0
	while level < max_level and experience >= _thresholds[level]:
		experience -= _thresholds[level]
		level += 1
		gained += 1
		leveled_up.emit(level)
	if is_max():
		experience = 0.0
	experience_gained.emit(amount)
	return gained


## Jumps to `new_level` (0 to `max_level`) with no experience toward the next one, emitting
## no signal. Returns false, reports an error through `LFLogger` and changes nothing when
## `new_level` is outside that range.
func set_level(new_level: int) -> bool:
	if new_level < 0 or new_level > max_level:
		_log.error('level must be from 0 to', max_level, 'got', new_level)
		return false
	level = new_level
	experience = 0.0
	return true


## Back to level 0 with no experience, emitting no signal. The thresholds stay.
func reset() -> void:
	level = 0
	experience = 0.0


func _checked_threshold(threshold: Variant) -> float:
	var is_number: bool = typeof(threshold) == TYPE_INT or typeof(threshold) == TYPE_FLOAT
	if is_number and is_finite(float(threshold)) and float(threshold) >= 0.0:
		return float(threshold)
	_log.error('thresholds must be finite numbers of 0 or more, got', threshold)
	return 0.0
