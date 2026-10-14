## A highlighted row in a list: stays inside the list, moves up and down without wrapping,
## and says which row gets a pointer prefix such as "> ".
##
## Use the instance (`new`) to hold the position, or the static helpers on a position you
## keep yourself. It draws nothing; you put `marker_at(i, "> ")` in front of each row's text.
class_name LFListCursor
extends RefCounted

## The highlighted row, always inside `0 .. count - 1` (0 for an empty list).
var index := 0
## How many rows the list has.
var count := 0


func _init(rows := 0, start := 0) -> void:
	count = maxi(rows, 0)
	index = clamp_index(start, count)


## `position` limited to a list of `rows` rows: 0 to `rows - 1`, or 0 for an empty list.
static func clamp_index(position: int, rows: int) -> int:
	return clampi(position, 0, maxi(rows - 1, 0))


## `position` moved by `delta` rows and stopped at both ends of a list of `rows` rows.
static func step(position: int, delta: int, rows: int) -> int:
	return clamp_index(position + delta, rows)


## `shown` when row `row` is the cursor's `position`, else `hidden`.
static func marker(row: int, position: int, shown: String, hidden := "") -> String:
	return shown if row == position else hidden


## The list now has `rows` rows; the cursor is pulled back if it fell off the end.
func set_count(rows: int) -> void:
	count = maxi(rows, 0)
	index = clamp_index(index, count)


## Moves by `delta` rows, stopping at the ends. Returns whether the cursor moved.
func move(delta: int) -> bool:
	var before := index
	index = step(index, delta, count)
	return index != before


## Jumps to `row`, limited to the list.
func move_to(row: int) -> void:
	index = clamp_index(row, count)


## `shown` for the cursor's row, else `hidden`.
func marker_at(row: int, shown: String, hidden := "") -> String:
	return marker(row, index, shown, hidden)
