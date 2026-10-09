# LFStateMachine, LFStateMachineConfig, LFStateTransition, LFStateHook, LFTransitionGuard, LFStateExitHook, LFStateEnterHook, LFAfterTransitionHook

> Keeps something in exactly one state at a time (closed, open...) and only lets it move between states along rules you write.

| | |
|---|---|
| **Files** | `lf_state_machine.gd`, `lf_state_machine_config.gd`, `lf_state_transition.gd`, `hooks/lf_state_hook.gd`, `hooks/lf_transition_guard.gd`, `hooks/lf_state_exit_hook.gd`, `hooks/lf_state_enter_hook.gd`, `hooks/lf_after_transition_hook.gd` |
| **Tests** | `tests/test_lf_state_machine.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` (tests use `LFUtils`) |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFStateMachine` | Object: create it with `.new()` |
| `LFStateMachineConfig` | Object: create it with `.new()` |
| `LFStateTransition` | Object: create it with `.new()` |
| `LFStateHook` | Object: create it with `.new()` |
| `LFTransitionGuard` | Object: create it with `.new()` |
| `LFStateExitHook` | Object: create it with `.new()` |
| `LFStateEnterHook` | Object: create it with `.new()` |
| `LFAfterTransitionHook` | Object: create it with `.new()` |

## When to use it

Use it when something in your game has clear modes and rules for moving between them: an
enemy that patrols, chases and attacks, a door that is closed, opening and open, or game
phases (menu, playing, game over). You declare which transitions exist and which states each may
start from, so an illegal jump (attacking while dead) is simply refused. Hooks run your code
on entering or leaving a state and can veto a transition, and they may `await` an
animation or a timer. For two or three states, an `enum` plus a `match` in `_process` is
simpler; for animation states alone, Godot's `AnimationTree` state machine fits better.

## Step by step

1. Make a scene: *Scene → New Scene*, then in the Scene dock click **Other Node**, pick **Node**, and press *Create*.
2. Right-click the new node, choose **Attach Script**, and press *Create* (the default name is fine). The script editor opens.
3. Select everything in the script and replace it with:

```gdscript
extends Node

# An enum is a named list of numbers. States and transitions are written as enums.
enum State { CLOSED, OPEN }
enum T { OPEN_DOOR, CLOSE_DOOR }

# Start CLOSED. Each transition says: its name, the states it may start from, where it leads.
var sm := LFStateMachine.new(LFStateMachineConfig.new(State.CLOSED, [
	LFStateTransition.new(T.OPEN_DOOR, [State.CLOSED], State.OPEN),
	LFStateTransition.new(T.CLOSE_DOOR, [State.OPEN], State.CLOSED),
]))


func _ready() -> void:
	# A signal is an event other code can listen to. This one fires after every state change.
	sm.state_entered.connect(_on_state_entered)

	print(sm.can_do(T.CLOSE_DOOR))  # false: a closed door can't be closed again
	await sm.do(T.OPEN_DOOR)        # "await" waits here until the change is finished
	print(sm.get_state() == State.OPEN)


func _on_state_entered(state: int) -> void:
	print("now ", State.keys()[state])
```

4. Press **F6** (*Run Current Scene*). Godot asks you to save the scene first: pick any name.
5. The **Output** panel shows `false`, `now OPEN` and `true`.
6. Replace the enums with your own states and transitions. To run code when a state starts, add hooks as the third argument of `LFStateMachineConfig.new` (see Usage below).

## API

Everything the class offers; you only need the rows used above to get started.

### LFStateMachine — Signals

| Member | Signature | Description |
|---|---|---|
| `state_exited` | `signal state_exited(state: int)` | After every `LFStateExitHook` for the previous state ran. |
| `state_entered` | `signal state_entered(state: int)` | After every `LFStateEnterHook` for the new state and every after-transition hook ran, once the machine is unlocked. A `do()` from a listener is queued until every listener has heard this state. |
| `transition_passed` | `signal transition_passed(transition: int)` | Right after `state_entered`, before any queued follow-up runs. |

### LFStateMachine — Methods

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFStateMachine.new(config: LFStateMachineConfig)` | Starts in `config.initial_state`; indexes transitions by `name` and hooks by the states/transitions they declare. A null config, a null transition (ignored), a transition declared twice (the first wins), `NO_STATE` used as a state, or an unknown hook type is reported. |
| `get_state` | `get_state() -> int` | The current state, or `NO_STATE` while a transition is between leaving one state and entering the next. |
| `NO_STATE` | `const NO_STATE := -1` | The mid-transition marker; never a real state id. |
| `get_transition_def` | `get_transition_def(transition: int) -> LFStateTransition` | The transition registered under `transition`, or `null`. |
| `can_do` | `can_do(transition: int) -> bool` | `false` while another transition is in progress; otherwise whether the current state is in the transition's `from`. |
| `do` | `do(transition: int) -> bool` (coroutine: a function that can wait; call it with `await`) | If `can_do`: runs guards (any `false` aborts, returns `false`), leave hooks, `state_exited`, switches state, enter hooks, after-transition hooks, unlocks, emits `state_entered` then `transition_passed`, runs any follow-up queued meanwhile; returns `true`. Otherwise returns `false`. Called from a `state_entered`/`transition_passed` listener, it waits until every listener has heard the current state, then runs and returns its own result. |

`can_do`/`do` return `false` for an unknown transition.

### LFStateMachineConfig

| Member | Signature | Description |
|---|---|---|
| `initial_state` | `var initial_state: int` | State the machine starts in. |
| `transitions` | `var transitions: Array[LFStateTransition]` | Every transition the machine knows. |
| `hooks` | `var hooks: Array[LFStateHook]` | Optional, defaults to empty. |
| `_init` | `LFStateMachineConfig.new(start_state: int, transition_list: Array[LFStateTransition], hook_list: Array[LFStateHook] = [])` | Sets the three properties. The arrays are kept, not copied; the machine reads them once, when built. |

### LFStateTransition

| Member | Signature | Description |
|---|---|---|
| `name` | `var name: int` | Transition id passed to `can_do`/`do`. |
| `from` | `var from: Array[int]` | Allowed source states. |
| `to` | `var to: int` | Target state. |
| `_init` | `LFStateTransition.new(transition_name: int, from_states: Array[int], to_state: int)` | Sets the three properties. |

### Hooks (`LFStateHook` is an empty marker base)

| Class | Constructor | Fires |
|---|---|---|
| `LFTransitionGuard` | `.new(guarded_transitions: Array[int], guard_callback: Callable = callback)` (default: always passes) | Before the transition; only a `callback` returning exactly `false` vetoes it — `null` (no return) or any other value, `0` included, lets it pass. |
| `LFStateExitHook` | `.new(on_states: Array[int], hook_callback: Callable)` | When leaving any listed state. |
| `LFStateEnterHook` | `.new(on_states: Array[int], hook_callback: Callable)` | When entering any listed state. |
| `LFAfterTransitionHook` | `.new(after_transitions: Array[int], hook_callback: Callable)` | After any listed transition completes. |

Each hook exposes its constructor arguments as `transitions`/`states` and `callback` properties. Callbacks take no arguments and are `await`ed in declaration order.

## Usage

```gdscript
extends Node

enum State { PATROL, CHASE, DEAD }
enum T { SPOT, LOSE, DIE }

var target_visible := false
var sm: LFStateMachine


func _ready() -> void:
	sm = LFStateMachine.new(LFStateMachineConfig.new(State.PATROL, [
		# id, the states it may start from, the state it leads to
		LFStateTransition.new(T.SPOT, [State.PATROL], State.CHASE),
		LFStateTransition.new(T.LOSE, [State.CHASE], State.PATROL),
		LFStateTransition.new(T.DIE, [State.PATROL, State.CHASE], State.DEAD),
	], [
		# Only spot the player if they really are visible (false vetoes).
		LFTransitionGuard.new([T.SPOT], func() -> bool: return target_visible),
		LFStateEnterHook.new([State.CHASE], func() -> void: print("roar!")),
		LFStateEnterHook.new([State.DEAD], _play_death),
	]))
	sm.state_entered.connect(func(state: int) -> void: print("now in ", State.keys()[state]))

	print(await sm.do(T.SPOT))  # false: the guard vetoed it, still PATROL
	target_visible = true
	print(await sm.do(T.SPOT))  # true: roar!, now in CHASE
	print(sm.can_do(T.SPOT))    # false: SPOT only starts from PATROL
	await sm.do(T.DIE)          # waits for the death hook to finish
	print(sm.get_state() == State.DEAD)  # true


func _play_death() -> void:
	await get_tree().create_timer(0.5).timeout  # e.g. wait for the animation
```

## Notes

- Only one transition runs at a time: a `do()` issued while another is awaiting a hook (guard, leave, enter or after-transition) is rejected (`false`), not queued. A guard rejection unlocks the machine again. A guard that waits (uses `await`) keeps the machine locked until it continues.
- `state_exited` is emitted while the machine is still locked, so a `do()` from its listener is refused.
- A listener can chain a follow-up `do()` from `state_entered`/`transition_passed`: it runs after every listener has heard the current state, so listeners always hear states in order and the last one heard is the real state.
- The config is checked on construction: a missing config, a transition declared twice (the first wins), `NO_STATE` used as a state, or a hook of an unknown type (ignored) is reported.
- A hook whose callback is invalid (empty, or its object freed) is reported and skipped; a guard like that lets the transition pass.
- After-transition hooks run before `state_entered` is emitted.
- `do()` is a coroutine (a function that can wait). If none of your hooks wait, it finishes immediately, so a bare `sm.do(x)` without `await` is fine in that case.
- Inside leave hooks `get_state()` is `LFStateMachine.NO_STATE`; don't use -1 as a real state id.
