extends GutTest

## Grades used by most tests, lowest first.
const LOW := &"low"
const MID := &"mid"
const HIGH := &"high"

var _combo: LFGradeCombo
var _changes := 0


func before_each():
	_changes = 0
	_combo = LFGradeCombo.new(
		[LOW, MID, HIGH],
		{LOW: 1.0, MID: 1.5, HIGH: 2.0},
		{LOW: 0.0, MID: 50.0, HIGH: 90.0},
	)
	_combo.changed.connect(_on_changed)


func _on_changed() -> void:
	_changes += 1


func test_a_new_combo_has_nothing_earned_and_a_factor_of_one():
	assert_eq(_combo.total(), 0)
	assert_eq(_combo.factor(), 1.0)
	assert_eq(_combo.apply(10.0), 10.0)


func test_adding_counts_the_grade_and_emits_changed():
	assert_true(_combo.add(MID))
	assert_true(_combo.add(MID, 2))
	assert_eq(_combo.count_of(MID), 3)
	assert_eq(_combo.count_of(LOW), 0)
	assert_eq(_combo.total(), 3)
	assert_eq(_changes, 2)


func test_an_unknown_grade_or_a_non_positive_amount_is_refused():
	assert_false(_combo.add(&"nope"))
	assert_false(_combo.add(MID, 0))
	assert_false(_combo.add(MID, -2))
	assert_eq(_combo.total(), 0)
	assert_eq(_changes, 0)
	assert_eq(_combo.count_of(&"nope"), 0)
	assert_push_error('LFGradeCombo')
	assert_push_error('LFGradeCombo')
	assert_push_error('LFGradeCombo')


func test_the_factor_adds_each_grades_excess_over_one_per_count():
	_combo.add(LOW, 5) # 1.0: adds nothing
	_combo.add(MID, 2) # +0.5 each
	_combo.add(HIGH) # +1.0
	assert_almost_eq(_combo.factor(), 3.0, 0.0001)
	assert_almost_eq(_combo.apply(4.0), 12.0, 0.0001)


func test_a_grade_without_a_given_factor_adds_nothing():
	var combo := LFGradeCombo.new([LOW, HIGH], {HIGH: 3.0})
	combo.add(LOW, 4)
	assert_eq(combo.factor(), 1.0)
	assert_eq(combo.factor_of(LOW), LFGradeCombo.DEFAULT_FACTOR)
	combo.add(HIGH)
	assert_almost_eq(combo.factor(), 3.0, 0.0001)


func test_set_factor_changes_the_worth_of_a_grade():
	_combo.add(MID, 2)
	assert_true(_combo.set_factor(MID, 2.0))
	assert_almost_eq(_combo.factor(), 3.0, 0.0001)
	assert_eq(_combo.factor_of(MID), 2.0)
	assert_false(_combo.set_factor(&"nope", 2.0))
	assert_false(_combo.set_factor(MID, NAN))
	assert_eq(_combo.factor_of(MID), 2.0, "refused values change nothing")
	assert_push_error('LFGradeCombo')
	assert_push_error('LFGradeCombo')


func test_penalize_removes_the_best_grades_first_rounding_up():
	_combo.add(LOW, 4)
	_combo.add(MID, 3)
	_combo.add(HIGH, 3) # 10 earned: 15% is 1.5, so 2 go
	_changes = 0
	assert_eq(_combo.penalize(), 2)
	assert_eq(_combo.count_of(HIGH), 1)
	assert_eq(_combo.count_of(MID), 3)
	assert_eq(_combo.count_of(LOW), 4)
	assert_eq(_changes, 1)


func test_penalize_continues_into_lower_grades():
	_combo.add(MID, 1)
	_combo.add(HIGH, 1)
	_combo.add(LOW, 2)
	assert_eq(_combo.penalize(0.75), 3)
	assert_eq(_combo.count_of(HIGH), 0)
	assert_eq(_combo.count_of(MID), 0)
	assert_eq(_combo.count_of(LOW), 1)


func test_penalize_edges():
	_combo.add(HIGH, 4)
	_changes = 0
	assert_eq(_combo.penalize(0.0), 0)
	assert_eq(_combo.penalize(-1.0), 0)
	assert_eq(_changes, 0, "removing nothing is not a change")
	assert_eq(_combo.penalize(5.0), 4, "at or above 1 removes everything")
	assert_eq(_combo.total(), 0)
	assert_eq(_combo.penalize(), 0, "nothing earned")
	assert_eq(_combo.penalize(NAN), 0)
	assert_push_error('LFGradeCombo')


func test_reset_forgets_everything_and_only_signals_a_real_change():
	_combo.reset()
	assert_eq(_changes, 0)
	_combo.add(HIGH, 2)
	_changes = 0
	_combo.reset()
	assert_eq(_combo.total(), 0)
	assert_eq(_combo.factor(), 1.0)
	assert_eq(_changes, 1)


func test_grade_for_score_picks_the_best_grade_reached():
	assert_eq(_combo.grade_for_score(95.0), HIGH)
	assert_eq(_combo.grade_for_score(90.0), HIGH, "a minimum is inclusive")
	assert_eq(_combo.grade_for_score(89.9), MID)
	assert_eq(_combo.grade_for_score(50.0), MID)
	assert_eq(_combo.grade_for_score(49.9), LOW)
	assert_eq(_combo.grade_for_score(-10.0), LOW, "below every minimum: the lowest grade")
	assert_eq(_combo.grade_for_score(NAN), LOW)


func test_grade_for_score_skips_grades_without_a_minimum():
	var combo := LFGradeCombo.new([LOW, MID, HIGH], {}, {HIGH: 10.0})
	assert_eq(combo.grade_for_score(5.0), LOW)
	assert_eq(combo.grade_for_score(50.0), HIGH)
	assert_true(combo.set_min_score(MID, 5.0))
	assert_eq(combo.grade_for_score(5.0), MID)
	assert_false(combo.set_min_score(&"nope", 1.0))
	assert_push_error('LFGradeCombo')


func test_a_combo_without_grades_answers_null_and_a_repeated_grade_is_kept_once():
	assert_null(LFGradeCombo.new([]).grade_for_score(1.0))
	var combo := LFGradeCombo.new([LOW, LOW, HIGH])
	assert_eq(combo.grades, [LOW, HIGH])
	assert_push_error('LFGradeCombo')


func test_grades_returns_a_copy():
	var listed := _combo.grades
	listed.clear()
	assert_eq(_combo.grades.size(), 3)


func test_grades_can_be_integers_such_as_enum_members():
	var combo := LFGradeCombo.new([2, 1, 0], {0: 3.0})
	combo.add(0)
	assert_almost_eq(combo.factor(), 3.0, 0.0001)
	assert_eq(combo.penalize(1.0), 1)
