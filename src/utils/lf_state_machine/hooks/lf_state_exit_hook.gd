## An `LFStateMachine` hook: a function awaited when the machine leaves any of its listed states.
class_name LFStateExitHook
extends LFStateHook


## States whose exit fires this hook.
var states: Array[int]
## Argument-less callable awaited on exit.
var callback: Callable


## A hook calling `hook_callback` (no arguments; may `await`) on leaving any of
## `on_states`.
func _init(on_states: Array[int], hook_callback: Callable) -> void:
	states = on_states
	callback = hook_callback
