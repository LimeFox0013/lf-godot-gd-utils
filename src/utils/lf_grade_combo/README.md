# LFGradeCombo

> A combo counter for graded results: count how many of each grade you earned, turn them into one multiplier, and take some away as a penalty.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_grade_combo.gd` |
| **Tests** | `tests/test_lf_grade_combo.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it when the player's timing or accuracy earns a grade ("OK", "Good", "Great", "Perfect")
and the grades add up into a bonus: a perfect-jump streak that boosts speed, a rhythm game's
combo, a throw that scores by how close it lands. It keeps the counts and does the sums; you
decide what a grade means and what to multiply. `penalize()` is the "you missed" button:
it takes a share of the earned grades away, best ones first. For a bad-luck streak that
raises the odds of a good *random* result use `LFPityTracker`; for per-player upgrade levels
use `LFModifierLevels`.

## Step by step

This makes a counter that prints the combined bonus.

1. In the Godot editor choose *Scene → New Scene*, click *Other Node*, pick **Node** and press *Create*.
2. Right-click the node, choose *Attach Script*, keep the defaults and press *Create*.
3. Replace the script's text with this:

```gdscript
extends Node

# Grades from lowest to highest. Each is worth a multiplier; "ok" is worth 1.0, which adds nothing.
var _combo := LFGradeCombo.new(
	[&"ok", &"good", &"great"],
	{&"ok": 1.0, &"good": 1.5, &"great": 2.0},
)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):      # Space or Enter: you did well
		_combo.add(&"great")
	elif event.is_action_pressed("ui_cancel"):    # Escape: you missed
		_combo.penalize()
	print("Earned: ", _combo.total(), "  multiplier: ", _combo.factor())
```
4. Save the scene (*Ctrl+S*, *Cmd+S* on macOS) and press **F6**.
5. Press Space three times: the multiplier goes 2.0, 3.0, 4.0 (each "great" adds 1.0). Press
   Escape: 15 % of what you earned (rounded up, so one) is removed, best first, and the
   multiplier drops back to 3.0.
6. Use your own grade names and numbers. To multiply something, call `_combo.apply(value)`.

## API

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_FACTOR` | `const DEFAULT_FACTOR := 1.0` | The multiplier of a grade none was given for: adds nothing. |
| `DEFAULT_PENALTY_FRACTION` | `const DEFAULT_PENALTY_FRACTION := 0.15` | The share `penalize` removes by default. |
| `_init` | `LFGradeCombo.new(initial_grades: Array, initial_factors := {}, initial_min_scores := {})` | Grades from lowest to highest (any values: StringNames, ints, enum members; a repeat is dropped with an error). `initial_factors` maps grade to multiplier. `initial_min_scores` maps grade to the lowest score earning it, for `grade_for_score`. |
| `grades` | `var grades: Array` | A copy of the grade list, lowest first. Read-only. |
| `changed` | `signal changed` | After the counts change (`add`, `penalize`, `reset`). |
| `add` | `add(grade, amount := 1) -> bool` | Earns `amount` of `grade`. False with an error for an unknown grade or an amount below 1. |
| `count_of` | `count_of(grade) -> int` | How many of that grade are earned; 0 for an unknown one. |
| `total` | `total() -> int` | All earned grades together. |
| `factor` | `factor() -> float` | `1.0 + (multiplier - 1.0) * count`, summed over the grades. |
| `apply` | `apply(value: float) -> float` | `value * factor()`. |
| `penalize` | `penalize(fraction := DEFAULT_PENALTY_FRACTION) -> int` | Removes `ceil(total * fraction)` grades, highest first; returns how many. At or below 0: none; at or above 1: all; a NaN is rejected with an error. |
| `reset` | `reset() -> void` | Forgets every earned grade. |
| `set_factor` / `factor_of` | `set_factor(grade, new_factor: float) -> bool` / `factor_of(grade) -> float` | Change or read a multiplier. |
| `set_min_score` | `set_min_score(grade, min_score: float) -> bool` | Sets the lowest score that earns a grade. |
| `grade_for_score` | `grade_for_score(score: float) -> Variant` | The best grade whose minimum score is at or below `score`; the lowest grade when none qualifies; null without grades. |

## Usage

A jump that is graded by how late the player pressed inside a timing window. The window
runs out from 100 % to 0 %, so a higher percentage left is better:

```gdscript
var _combo := LFGradeCombo.new(
	[&"ok", &"good", &"great", &"perfect"],
	{&"ok": 1.0, &"good": 1.2, &"great": 1.5, &"perfect": 2.0},
	{&"ok": 0.0, &"good": 55.0, &"great": 76.0, &"perfect": 96.5},   # percent of the window left
)

func on_jump(window_left_percent: float) -> void:
	var grade: StringName = _combo.grade_for_score(window_left_percent)
	_combo.add(grade)
	speed = base_speed * _combo.factor()

func on_missed_jump() -> void:
	_combo.penalize()          # lose 15 % of the earned grades, best first
	speed = base_speed * _combo.factor()
```

## Notes

- A grade worth `1.0` adds nothing to the factor, however many you earn; it still counts in `total()` and for `penalize()`.
- `penalize()` removes from the top: a streak of "perfect" melts before the "ok"s. Rounding is up, so any penalty on a non-empty combo removes at least one grade.
- The class only counts. Showing the counts (labels, panels) is yours; connect to `changed`.
- A signal on a RefCounted object keeps the object alive while a lambda that uses `self` is connected: connect a method.
