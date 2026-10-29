## A combo counter for graded results: count how many of each grade were earned, turn them into one
## combined multiplier, and take some away as a penalty.
##
## Give it the grades (any values: StringNames, ints, enum members) from lowest to highest,
## each with a multiplier. `add(grade)` earns one; `factor()` is the combined multiplier
## (1.0 plus `(multiplier - 1.0)` for every grade earned); `apply(value)` multiplies a value by
## it; `penalize()` removes a share of the earned grades, best ones first. A score can be
## turned into a grade with `grade_for_score` (a timing window, a distance, a percentage).
class_name LFGradeCombo
extends RefCounted

## The multiplier a grade has when none is given: it adds nothing to the combo.
const DEFAULT_FACTOR := 1.0
## The share of the earned grades `penalize` removes when none is given.
const DEFAULT_PENALTY_FRACTION := 0.15

## Emitted after the counters change (`add`, `penalize`, `reset`).
signal changed

static var _log := LFLogger.new()

## Every grade, from the lowest to the highest. Read-only: set it through `new`.
var grades: Array:
	get:
		return _grades.duplicate()

var _grades: Array = []
var _factors := {} # grade -> float
var _min_scores := {} # grade -> float
var _counts := {} # grade -> int


## A combo over `initial_grades`, lowest first (a repeated grade is kept once). `initial_factors` maps a
## grade to its multiplier (missing: `DEFAULT_FACTOR`); `initial_min_scores` maps a grade to the lowest
## score that earns it, for `grade_for_score`.
func _init(initial_grades: Array, initial_factors := {}, initial_min_scores := {}) -> void:
	for grade: Variant in initial_grades:
		if _counts.has(grade):
			_log.error("LFGradeCombo: the grade %s is listed twice; keeping the first" % [grade])
			continue
		_grades.append(grade)
		_counts[grade] = 0
		_factors[grade] = float(initial_factors.get(grade, DEFAULT_FACTOR))
		if initial_min_scores.has(grade):
			_min_scores[grade] = float(initial_min_scores[grade])


## Earns `amount` of `grade`. False (and an error) for a grade this combo doesn't know, or an
## amount below 1; nothing changes then.
func add(grade: Variant, amount := 1) -> bool:
	if !_counts.has(grade):
		_log.error("LFGradeCombo: unknown grade %s" % [grade])
		return false
	if amount < 1:
		_log.error("LFGradeCombo: cannot add %d of a grade" % amount)
		return false
	_counts[grade] += amount
	changed.emit()
	return true


## How many of `grade` are earned; 0 for an unknown grade.
func count_of(grade: Variant) -> int:
	return _counts.get(grade, 0)


## How many grades are earned, all kinds together.
func total() -> int:
	var sum := 0
	for count: int in _counts.values():
		sum += count
	return sum


## The combined multiplier: 1.0 plus `(multiplier - 1.0) * count` for every grade. A grade with
## the default multiplier adds nothing.
func factor() -> float:
	var combined := 1.0
	for grade: Variant in _grades:
		combined += (float(_factors[grade]) - 1.0) * _counts[grade]
	return combined


## `value` times the combined multiplier.
func apply(value: float) -> float:
	return value * factor()


## Removes the best earned grades until `ceil(total * fraction)` are gone, highest grade first, and
## returns how many were removed. At or below 0 (or with nothing earned) none; at or above 1
## all. A NaN is rejected: an error, and none are removed.
func penalize(fraction := DEFAULT_PENALTY_FRACTION) -> int:
	if is_nan(fraction):
		_log.error("LFGradeCombo: a NaN penalty fraction is rejected")
		return 0
	var to_remove := ceili(total() * clampf(fraction, 0.0, 1.0))
	var removed := 0
	for i in range(_grades.size() - 1, -1, -1):
		var grade: Variant = _grades[i]
		var take := mini(_counts[grade], to_remove - removed)
		_counts[grade] -= take
		removed += take
		if removed >= to_remove:
			break
	if removed > 0:
		changed.emit()
	return removed


## Forgets every earned grade.
func reset() -> void:
	if total() == 0:
		return
	for grade: Variant in _grades:
		_counts[grade] = 0
	changed.emit()


## Sets the multiplier of `grade`. False (and an error) for an unknown grade or a NaN.
func set_factor(grade: Variant, new_factor: float) -> bool:
	if !_counts.has(grade) or is_nan(new_factor):
		_log.error("LFGradeCombo: cannot set the multiplier of %s to %s" % [grade, new_factor])
		return false
	_factors[grade] = new_factor
	return true


## The multiplier of `grade`; `DEFAULT_FACTOR` for an unknown grade.
func factor_of(grade: Variant) -> float:
	return _factors.get(grade, DEFAULT_FACTOR)


## Sets the lowest score that earns `grade`. False (and an error) for an unknown grade or a NaN.
func set_min_score(grade: Variant, min_score: float) -> bool:
	if !_counts.has(grade) or is_nan(min_score):
		_log.error("LFGradeCombo: cannot set the minimum score of %s to %s" % [grade, min_score])
		return false
	_min_scores[grade] = min_score
	return true


## The best grade whose minimum score is at or below `score`; the lowest grade when none
## qualifies (or the score is NaN); null when the combo has no grades. Grades without a minimum
## score are never chosen by a score, except as that lowest fallback.
func grade_for_score(score: float) -> Variant:
	if _grades.is_empty():
		return null
	if !is_nan(score):
		for i in range(_grades.size() - 1, -1, -1):
			var grade: Variant = _grades[i]
			if _min_scores.has(grade) and score >= _min_scores[grade]:
				return grade
	return _grades[0]
