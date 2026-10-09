## Takes turns between participants: one acts at a time, each turn and the whole stage are timed.
##
## A round-robin (everyone in order, then back to the first) over participant ids: each
## turn has its own timer, and an overall stage timer backstops the whole cycle. Time
## comes from the caller (`tick(delta)`), so it follows a simulation's own clock. The
## *stage* is the whole cycle's time limit (one round of turns, or a whole phase).
##
## A turn ends on `end_turn()` (the participant acted), when its timer runs out (only that
## turn is lost), or when the participant is marked done (`mark_done`: out for the rest of
## the cycle). Done participants are passed over, and so are turns a participant must
## skip (`skip_turns`). Once started, the cycle finishes when every participant is done or
## the stage timer runs out; before `start()` nothing finishes.
##
## The caller decides which turns need no input: `auto_resolve` is called at the start of
## each turn and may act for the participant (call `end_turn()` or `mark_done(id)`, or
## return true) so the cycle moves straight on. A loop guard stops a run of turns ended
## without waiting (by `auto_resolve`, or by a `turn_started` listener calling `end_turn()`)
## that never marks anyone done; the turn it stops on then waits for its timer like any
## other.
class_name LFTurnCycle
extends RefCounted


## Emitted when a participant's turn begins (not for a done participant or a skipped
## turn), before `auto_resolve` is asked about it.
signal turn_started(id: Variant)
## Emitted once, when every participant is done or the stage timer ran out.
signal finished

## Default `max_auto_turns`: 0, which sizes the loop guard from the order
## (`order.size() * 2 + 1`).
const DEFAULT_MAX_AUTO_TURNS := 0

## Seconds a turn may last before it is lost.
var turn_seconds: float
## Seconds the whole cycle may last (INF for no limit).
var stage_seconds: float
## `Callable(id) -> bool`, called at the start of each turn. Returning true (any other
## value counts as false), or calling `end_turn()` or `mark_done(id)` from inside it, ends
## the turn at once; otherwise the turn waits for input. Leave it empty when every turn
## waits for input.
var auto_resolve: Callable
## How many turns in a row ended without waiting (by `auto_resolve` or a `turn_started`
## listener, with nobody newly done) one settling may run before the guard stops it; 0 or
## less uses `order.size() * 2 + 1`.
var max_auto_turns := DEFAULT_MAX_AUTO_TURNS

var _order: Array = []
var _done: Array
var _skips := {}
var _index := 0
var _turn_elapsed := 0.0
var _elapsed := 0.0
var _finished := false
## Set by the first `start()`; until then `tick` and `end_turn` do nothing.
var _started := false
## True while turns are being settled: `end_turn`/`mark_done` called then are recorded
## for the settling loop instead of starting a nested one.
var _settling := false
var _end_requested := false


## A cycle over `participant_order` (copied), with `turn_seconds_limit` seconds per turn
## and `stage_seconds_limit` for the whole cycle (INF for no limit). `done` is the array
## the done ids are kept in; pass your own to share it (it is used, not copied, and ids
## added to it count as done). Call `start()` once to begin.
func _init(participant_order: Array, turn_seconds_limit: float, stage_seconds_limit: float, done: Array = []) -> void:
	_order = participant_order.duplicate()
	turn_seconds = turn_seconds_limit
	stage_seconds = stage_seconds_limit
	_done = done


## Begins the first turn (passing over done participants and asking `auto_resolve`). An
## empty order, or one whose participants are all done, finishes at once. Calling it again
## mid-cycle re-settles the current turn without touching the timers (for when what
## `auto_resolve` would decide has changed); `turn_started` fires for it again.
func start() -> void:
	_started = true
	_settle()


## The participants in turn order (a copy).
func order() -> Array:
	return _order.duplicate()


## The participant whose turn it is (before `start()`, the first in the order), or null
## once finished (or with an empty order).
func current() -> Variant:
	if _finished or _order.is_empty():
		return null
	return _order[_index]


## Advances both timers by `delta` seconds (a negative or non-finite delta adds nothing).
## The stage timer running out finishes the cycle; otherwise the turn timer running out
## ends the turn. Does nothing before `start()` (the timers don't run yet) or once finished.
func tick(delta: float) -> void:
	if _finished or not _started:
		return
	if is_finite(delta) and delta > 0.0:
		_elapsed += delta
		_turn_elapsed += delta
	if _elapsed >= stage_seconds:
		_finish()
		return
	if _turn_elapsed >= turn_seconds:
		end_turn()


## Ends the current turn and moves to the next participant that needs a turn. Does
## nothing before `start()` or once finished.
func end_turn() -> void:
	if _finished or not _started:
		return
	if _settling:
		_end_requested = true
		return
	_turn_elapsed = 0.0
	if _all_done():
		_finish()
		return
	_step()
	_settle()


## Takes `id` out of the rest of the cycle and returns true; false once finished, for an
## id not in the order, or one already done. Ends its turn if it was its turn, and
## finishes the cycle when it was the last one left. Before `start()` it only records `id`
## as done, even for the last one left: like `tick` and `end_turn`, nothing runs before
## `start()`, which then passes over done ids (and finishes at once if all are done).
## Ids of different types (`[1, "bot"]`) are compared without errors (`LFUtils.same_value`).
func mark_done(id: Variant) -> bool:
	if _finished or not _order.has(id) or _done.has(id):
		return false
	_done.append(id)
	if _settling or not _started:
		return true
	if LFUtils.same_value(id, current()):
		end_turn()
	elif _all_done():
		_finish()
	return true


## Whether `id` is done.
func is_done(id: Variant) -> bool:
	return _done.has(id)


## The done ids, in the order they were marked (a copy).
func done_ids() -> Array:
	return _done.duplicate()


## `id` loses its next `turns` turns in this cycle (e.g. a participant held back for a while); adds to any
## turns it already has to skip. A non-positive count changes nothing.
func skip_turns(id: Variant, turns: int) -> void:
	if turns <= 0:
		return
	_skips[id] = int(_skips.get(id, 0)) + turns


## Turns `id` still has to skip.
func skips_left(id: Variant) -> int:
	return int(_skips.get(id, 0))


## Seconds left in the current turn, never negative.
func turn_time_left() -> float:
	return maxf(turn_seconds - _turn_elapsed, 0.0)


## Seconds left before the stage timer finishes the cycle, never negative.
func stage_time_left() -> float:
	return maxf(stage_seconds - _elapsed, 0.0)


## Whether the cycle has finished.
func is_finished() -> bool:
	return _finished


## Moves past turns that need no input: done participants and skipped turns are passed
## over, and a turn `auto_resolve` takes care of ends at once.
func _settle() -> void:
	if _settling:
		return
	_settling = true
	var limit := max_auto_turns if max_auto_turns > 0 else _order.size() * 2 + 1
	var auto_turns := 0
	while not _finished:
		if _all_done():
			_finish()
			break
		var id: Variant = _order[_index]
		if _done.has(id):
			_step()
			continue
		if int(_skips.get(id, 0)) > 0:
			_skips[id] = int(_skips[id]) - 1
			_step()
			continue
		_end_requested = false
		var done_before := _done.size()
		turn_started.emit(id)
		var resolved := false
		if not _finished and not _end_requested and not _done.has(id) and auto_resolve.is_valid():
			if auto_turns >= limit:
				break
			var answer: Variant = auto_resolve.call(id)
			resolved = answer is bool and answer
		if _finished:
			break
		if not (resolved or _end_requested or _done.has(id)):
			break
		if _done.size() != done_before:
			auto_turns = 0
		elif auto_turns >= limit:
			# A turn ended from a `turn_started` listener (not `auto_resolve`, which is guarded
			# above): stop here too, or listeners ending every turn would never let this return.
			break
		else:
			auto_turns += 1
		_step()
	_end_requested = false
	_settling = false


func _step() -> void:
	_turn_elapsed = 0.0
	# Every caller first finishes the cycle when all are done, which an empty order always is.
	_index = (_index + 1) % _order.size()


func _all_done() -> bool:
	for id: Variant in _order:
		if not _done.has(id):
			return false
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()
