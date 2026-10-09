## One named move of an `LFStateMachine`: the states it may start from and the state it leads to.
class_name LFStateTransition
extends RefCounted


## Transition id passed to `LFStateMachine.can_do()`/`LFStateMachine.do()`.
var name: int
## States this transition may be taken from.
var from: Array[int]
## State this transition leads to.
var to: int


## A transition with id `transition_name`, allowed from any of `from_states`, leading to
## `to_state`.
func _init(transition_name: int, from_states: Array[int], to_state: int) -> void:
	name = transition_name
	from = from_states
	to = to_state
