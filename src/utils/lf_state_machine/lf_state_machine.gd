## A state machine: an object that is in exactly one state at a time (idle, loading, running)
## and changes state only through transitions you declare.
##
## States and transitions are ints (use your own enums). Build it from an `LFStateMachineConfig`, then
## call `do(transition)`. Hooks (`LFTransitionGuard`, `LFStateExitHook`,
## `LFStateEnterHook`, `LFAfterTransitionHook`) can veto a transition or run code when a
## state is left or entered or a transition completes; they may `await`. Only one
## transition runs at a time.
class_name LFStateMachine
extends RefCounted

static var _log := LFLogger.new()

## What `get_state()` reports while a transition is between leaving one state and entering
## the next (inside leave hooks). Never use -1 as a real state id.
const NO_STATE := -1

var _state: int
var _passing := false
## While `state_entered`/`transition_passed` are being emitted: a `do()` called then is
## queued and runs once every listener has heard the current state.
var _emitting := false
## [transition, id] pairs waiting for the emission to finish.
var _queue: Array = []
var _next_queued_id := 0
signal _queued_done(id: int, ok: bool)

var _transition_defs: Dictionary[int, LFStateTransition] = {}
var _hooks := {
	LFTransitionGuard: {},
	LFStateExitHook: {},
	LFStateEnterHook: {},
	LFAfterTransitionHook: {},
}

## Emitted after every leave hook for the previous `state` ran (the machine is still
## locked: a `do()` from a listener is refused).
signal state_exited(state: int)
## Emitted after every enter hook for the new `state` and every after-transition hook ran,
## once the machine is unlocked. A `do()` from a listener is queued and runs after every
## listener has heard this state.
signal state_entered(state: int)
## Emitted last in a successful `do()`, right after `state_entered`, before any queued
## follow-up runs.
signal transition_passed(transition: int)


## A machine built from `config`, starting in `config.initial_state`. The config is checked: a
## null config, a null transition (ignored), a transition declared twice (the first wins),
## `NO_STATE` used as a state, or an unknown hook type is reported.
func _init(config: LFStateMachineConfig) -> void:
	if config == null:
		_log.error("LFStateMachine: no config; the machine has no states")
		_state = NO_STATE
		return
	_state = config.initial_state
	if config.initial_state == NO_STATE:
		_log.error("LFStateMachine: NO_STATE can't be the initial state")
	for transition_def in config.transitions:
		if transition_def == null:
			_log.error("LFStateMachine: a null transition is ignored")
			continue
		if transition_def.to == NO_STATE or transition_def.from.has(NO_STATE):
			_log.error("LFStateMachine: transition %d uses NO_STATE as a state" % transition_def.name)
		if _transition_defs.has(transition_def.name):
			_log.error("LFStateMachine: transition %d is declared twice; the first declaration is kept" % transition_def.name)
			continue
		_transition_defs[transition_def.name] = transition_def
	for hook in config.hooks:
		var keys: Array
		var kind: Variant
		if hook is LFTransitionGuard:
			kind = LFTransitionGuard
			keys = hook.transitions
		elif hook is LFAfterTransitionHook:
			kind = LFAfterTransitionHook
			keys = hook.transitions
		elif hook is LFStateExitHook:
			kind = LFStateExitHook
			keys = hook.states
		elif hook is LFStateEnterHook:
			kind = LFStateEnterHook
			keys = hook.states
		else:
			_log.error("LFStateMachine: unknown hook type, ignored")
			continue
		for key: Variant in keys:
			if not _hooks[kind].has(key):
				_hooks[kind][key] = []
			_hooks[kind][key].append(hook)


## The current state, or NO_STATE mid-transition.
func get_state() -> int:
	return _state


## The transition registered under `transition`, or null if there is none.
func get_transition_def(transition: int) -> LFStateTransition:
	return _transition_defs.get(transition)


## Whether `do(transition)` would start now: `transition` is known, no other transition is
## in progress, and the current state is one of its `from` states. An unknown transition
## is simply `false` (not an error).
func can_do(transition: int) -> bool:
	if _passing:
		return false

	var transition_def := get_transition_def(transition)
	if transition_def != null and _state in transition_def.from:
		return true

	return false


## Coroutine (call it with `await`). If `can_do`, runs guards (only a guard returning exactly `false` aborts; `null`,
## no return or any other value passes), leave hooks, `state_exited`, switches state, enter hooks,
## after-transition hooks, unlocks, emits `state_entered` and `transition_passed`, runs any
## `do()` a listener asked for meanwhile, then returns true. Returns false otherwise. A hook
## whose callback is invalid (empty, or its object freed) is reported and skipped. A
## `do()` called from a `state_entered`/`transition_passed` listener waits until every
## listener has heard the current state, then runs and returns its own result.
func do(transition: int) -> bool:
	if _emitting:
		var id := _next_queued_id
		_next_queued_id += 1
		_queue.append([transition, id])
		while true: # left only through the return below
			var done: Array = await _queued_done
			if done[0] == id:
				return done[1]
	if not can_do(transition):
		return false
	var transition_def := get_transition_def(transition)
	_passing = true

	if _hooks[LFTransitionGuard].has(transition):
		for guard_hook: Variant in _hooks[LFTransitionGuard][transition]:
			var verdict: Variant = await _call_hook(guard_hook)
			# Compared by type: `0 == false` and `"" == false` are script errors, and they
			# would leave the machine locked for good.
			if typeof(verdict) == TYPE_BOOL and not verdict:
				# Unlock before returning: can_do() refuses everything while _passing is set.
				_passing = false
				return false

	var previous_state := _state
	_state = NO_STATE
	if _hooks[LFStateExitHook].has(previous_state):
		for hook: Variant in _hooks[LFStateExitHook][previous_state]:
			await _call_hook(hook)
	state_exited.emit(previous_state)

	_state = transition_def.to
	if _hooks[LFStateEnterHook].has(_state):
		for hook: Variant in _hooks[LFStateEnterHook][_state]:
			await _call_hook(hook)
	if _hooks[LFAfterTransitionHook].has(transition):
		for hook: Variant in _hooks[LFAfterTransitionHook][transition]:
			await _call_hook(hook)

	_passing = false
	_emitting = true
	state_entered.emit(transition_def.to)
	transition_passed.emit(transition)
	_emitting = false
	while not _queue.is_empty():
		var queued: Array = _queue.pop_front()
		_queued_done.emit(queued[1], await do(queued[0]))
	return true


## Awaits `hook.callback`. An invalid callable (empty, or its object freed) is reported and
## skipped: calling it would abort `do()` with the machine still locked.
func _call_hook(hook: Variant) -> Variant:
	if not hook.callback.is_valid():
		_log.error("LFStateMachine: a hook's callback is invalid (empty or its object freed); skipped")
		return null
	return await hook.callback.call()
