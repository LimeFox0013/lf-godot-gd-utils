## An `LFStateMachine` hook: a function awaited after any of its listed transitions completes.
class_name LFAfterTransitionHook
extends LFStateHook


## Transitions this hook fires after.
var transitions: Array[int]
## Argument-less callable awaited after the transition.
var callback: Callable


## A hook calling `hook_callback` (no arguments; may `await`) after any of
## `after_transitions` completes.
func _init(after_transitions: Array[int], hook_callback: Callable) -> void:
	transitions = after_transitions
	callback = hook_callback
