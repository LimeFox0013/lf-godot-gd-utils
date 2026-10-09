## An `LFStateMachine` hook that can stop a transition: a function asked before any of its listed transitions.
##
## Only a callback returning exactly `false` vetoes the transition; returning `true`,
## `null`, nothing or any other value (`0` included) lets it pass.
class_name LFTransitionGuard
extends LFStateHook


## Transitions this guard checks.
var transitions: Array[int]
## Argument-less callable returning whether the transition may proceed. May `await`; the
## machine stays locked until it returns.
var callback: Callable = func () -> bool: return true


## A guard asking `guard_callback` (no arguments) before any of `guarded_transitions`.
## Without a callback it always lets the transition pass.
func _init(guarded_transitions: Array[int], guard_callback: Callable = callback) -> void:
	transitions = guarded_transitions
	callback = guard_callback
