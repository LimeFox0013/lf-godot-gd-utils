# LFTurnCycle

> A timed round-robin over participant ids: per-turn and whole-stage timers on caller time, participants marked done, skipped turns, and a hook that resolves turns needing no input.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_turn_cycle.gd` |
| **Tests** | `tests/test_lf_turn_cycle.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFUtils` (`same_value`) |

## When to use it

Use it for anything where participants act one after another under a clock: a tactics
game where each player gets 12 s per move and the stage ends after 90 s, a board game
with bots that move instantly, a party game where a stunned player loses their next turn.
It tracks whose turn it is, both timers, who is out (done) and who must skip, and lets
bots or "no legal move" cases resolve themselves via `auto_resolve`. It does no game
logic and runs on the delta you give it. The *stage* is the whole cycle's time limit
(one round of turns, or a whole match phase). For a plain repeating timer use
`LFIntervalTimer`; for general state machines (menus, AI) use `LFStateMachine`.

## Step by step

A turn cycle tracks whose turn it is among a list of players. It has no game
logic of its own: it tells you when a turn starts and ends, and you act on that.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock (top left) click
   *Other Node*, pick *Node*, and press *Create*.
2. Right-click the new node and choose *Attach Script*. Keep the defaults in the dialog
   and press *Create*. The script editor opens.
3. Select everything in the script and replace it with this code:

```gdscript
extends Node

var turns: LFTurnCycle

func _ready() -> void:
	# Players "alice" and "bob"; 3 seconds per turn; the whole stage lasts 20 seconds.
	turns = LFTurnCycle.new(["alice", "bob"], 3.0, 20.0)
	# Signals are events other code can listen to. Connect a function to each.
	turns.turn_started.connect(_on_turn_started)
	turns.finished.connect(_on_finished)
	turns.start()                # begin the first turn

func _process(delta: float) -> void:
	turns.tick(delta)            # feed it the seconds since the last frame

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):   # Space or Enter = "I'm done with my turn"
		turns.end_turn()

func _on_turn_started(id: Variant) -> void:
	print("It is ", id, "'s turn")

func _on_finished() -> void:
	print("Stage over")
```
4. Press *Ctrl+S* (*Cmd+S* on macOS) and save the scene, then *F6* (*Run Current Scene*).
5. In the *Output* panel `It is alice's turn` appears at once. Press *Space* or *Enter*
   and it becomes bob's turn. If you do nothing, the turn passes by itself after 3
   seconds. After 20 seconds in total, `Stage over` prints and the turns stop.
6. Replace `["alice", "bob"]` with your own player names (any values work as ids) and the
   two numbers with your limits in seconds. Use `turns.mark_done("bob")` to take a player
   out of the rest of the stage.

## API

Everything the class offers; you only need the rows used above to get started.

### Signals

| Member | Signature | Description |
|---|---|---|
| `turn_started` | `signal turn_started(id: Variant)` | A participant's turn begins (never for a done participant or a skipped turn), before `auto_resolve` is asked. |
| `finished` | `signal finished` | Once: every participant is done, or the stage timer ran out. |

### Properties

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_MAX_AUTO_TURNS` | `const int = 0` | Default `max_auto_turns`: 0 sizes the loop guard from the order (`order.size() * 2 + 1`). |
| `turn_seconds` | `var turn_seconds: float` | Seconds a turn may last before it is lost. |
| `stage_seconds` | `var stage_seconds: float` | Seconds the whole cycle may last; `INF` for no limit. |
| `auto_resolve` | `var auto_resolve: Callable` | `(id) -> bool`, called at the start of each turn. Returning true (any other value counts as false), or calling `end_turn()` / `mark_done(id)` from inside, ends the turn at once; otherwise the turn waits for input. Empty: every turn waits. |
| `max_auto_turns` | `var max_auto_turns := DEFAULT_MAX_AUTO_TURNS` (0) | The loop guard: turns in a row ended without waiting (by `auto_resolve`, or by a `turn_started` listener calling `end_turn()`, with nobody newly done) one settling may run. 0 or less means `order.size() * 2 + 1`. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFTurnCycle.new(participant_order: Array, turn_seconds_limit: float, stage_seconds_limit: float, done: Array = [])` | `participant_order` is copied. `done` holds the done ids; pass your own array to share it (used, not copied: ids you add to it count as done). |
| `start` | `start() -> void` | Begins the first turn. Again mid-cycle: re-settles the current turn (timers untouched), e.g. once `auto_resolve` would decide differently. |
| `current` | `current() -> Variant` | Whose turn it is (before `start()`, the first in the order); null once finished or with an empty order. |
| `order` | `order() -> Array` | The turn order (a copy). |
| `tick` | `tick(delta: float) -> void` | Advances both timers by `delta` seconds (a negative or non-finite delta adds nothing). The stage timer running out finishes; else the turn timer running out ends the turn. Does nothing before `start()`. |
| `end_turn` | `end_turn() -> void` | The current participant acted: move to the next one that needs a turn. Does nothing before `start()`. |
| `mark_done` | `mark_done(id: Variant) -> bool` | Out for the rest of the cycle; ends its turn if it was its turn, finishes when it was the last. False once finished, for an id not in the order, or one already done. Before `start()` it only records the id, even the last one left: nothing finishes before `start()`, which passes over done ids and finishes at once if all are done. Ids of mixed types (`[1, "bot"]`) are compared without errors. |
| `is_done` | `is_done(id: Variant) -> bool` | Whether `id` is done. |
| `done_ids` | `done_ids() -> Array` | The done ids in the order they were marked (a copy). |
| `skip_turns` | `skip_turns(id: Variant, turns: int) -> void` | `id` loses its next `turns` turns; adds up. A non-positive count changes nothing. |
| `skips_left` | `skips_left(id: Variant) -> int` | Turns `id` still has to skip. |
| `turn_time_left` | `turn_time_left() -> float` | Seconds left in this turn, never negative. |
| `stage_time_left` | `stage_time_left() -> float` | Seconds left before the stage timer finishes the cycle, never negative. |
| `is_finished` | `is_finished() -> bool` | Whether it has finished. |

## Usage

```gdscript
# stage.gd — on the Node that runs one stage (here, one round) of a turn-based match
extends Node

var bots := ["bot-1"]
var turns: LFTurnCycle

func _ready() -> void:
	# 12 s per turn, 90 s for the whole stage.
	turns = LFTurnCycle.new(["alice", "bob", "bot-1"], 12.0, 90.0)
	turns.auto_resolve = _resolve_without_input   # a method, not a lambda holding `turns`
	turns.turn_started.connect(_on_turn_started)
	turns.finished.connect(_on_stage_over)
	turns.start()

func _process(delta: float) -> void:
	turns.tick(delta)                 # nothing advances unless you tick it

func _resolve_without_input(id: Variant) -> bool:
	if id in bots:
		print(id, " plays instantly")
		return true                   # the bot acted: next turn
	return false                      # wait for this player's input (or the turn timer)

func _on_turn_started(id: Variant) -> void:
	print("Your turn, ", id, " (", turns.turn_time_left(), " s)")

func on_player_move(id: Variant) -> void:   # call this from your input/UI code
	if id == turns.current():
		turns.end_turn()

func on_player_out_of_moves(id: Variant) -> void:
	turns.mark_done(id)               # out for the rest of the stage

func _on_stage_over() -> void:
	print("Stage over")
```

## Notes

- Time is whatever the caller passes to `tick`; nothing runs on its own. Pass `INF` as the stage limit for no backstop.
- `end_turn` and `mark_done` can be called from `auto_resolve` and from `turn_started` listeners: while turns are being settled they are recorded and acted on by the running loop rather than starting a nested one (`start` does nothing then).
- The loop guard stops an endless run of turns that end without waiting (an `auto_resolve` that always returns true, or a `turn_started` listener that always calls `end_turn()`, would otherwise spin forever). When it stops on a turn a listener just ended, that `end_turn()` is dropped. The turn it stops on waits for its timer like any other, and its timeout starts a fresh, freshly guarded run. Raise `max_auto_turns` when one participant may legitimately resolve many turns in a row while everyone else is done.
- A done participant is never asked again and gets no `turn_started`; a skipped turn uses up one skip and gets no `turn_started` either.
- An empty order, or one whose participants are all done, finishes on `start()`. Before
  `start()` the cycle never finishes: `tick` and `end_turn` do nothing and `mark_done` only
  records the id.
- Set `auto_resolve` to a method of your script (as above), not to an inline `func(...)` that uses the cycle: that keeps the cycle in memory until `auto_resolve` is cleared.
