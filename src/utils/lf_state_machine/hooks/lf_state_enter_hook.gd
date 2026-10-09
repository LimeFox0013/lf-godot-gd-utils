## An `LFStateMachine` hook: a function awaited when the machine enters any of its listed states.
class_name LFStateEnterHook
extends LFStateHook


## States whose entry fires this hook.
var states: Array[int]
## Argument-less callable awaited on entry.
var callback: Callable


## A hook calling `hook_callback` (no arguments; may `await`) on entering any of
## `on_states`.
func _init(on_states: Array[int], hook_callback: Callable) -> void:
	states = on_states
	callback = hook_callback
